//
//  ImageBoard.swift
//  MetalImage
//
//  Created by M.Ike on 2016/02/06.
//  Copyright © 2016年 M.Ike. All rights reserved.
//

import UIKit
import MetalKit

/* シェーダとやりとりする用 */
struct PieceParameter {
    var delta: float4
    var time: float4
}

struct ImagePiece {
    var position: float4
    var color: float4
    var acc: float4
}


// MARK: -
class ImageBoard: RenderProtocol, ComputeProtocol {
    let TotalLoopTime = Float(7.3)  // 1回のループ時間
    let FallSpeed = Float(-1.5)     // 落下速度
    let FallTarget = Float(-1)      // 落下地点
    let FallDelay = Float(0.01)     // 落下のdelay
    
    // Indices of vertex attribute in descriptor.
    enum VertexAttribute: Int {
        case Piece = 0
        case Uniform = 1
        func index() -> Int { return self.rawValue }
    }
    
    enum TextureType: Int {
        case Image = 0
        func index() -> Int { return self.rawValue }
    }

    enum ComputeBuffer: Int {
        case Piece = 0
        case Parameter = 1
        func index() -> Int { return self.rawValue }
    }
    
    private var pipelineState: MTLRenderPipelineState! = nil
    private var depthState: MTLDepthStencilState! = nil
    
    private var renderBuffer: MTLBuffer! = nil
    private var frameUniformBuffer: MTLBuffer! = nil
    
    /* compute */
    // 実行させるパイプライン
    private var activeComputeState: MTLComputePipelineState! = nil
    // 初期設定用パイプライン
    private var setupComputeState: MTLComputePipelineState! = nil
    // 実行用のパイプライン
    private var computeState: MTLComputePipelineState! = nil
    
    private var parameterBuffer: MTLBuffer! = nil
    private var imageTexture: MTLTexture! = nil
    
    private var threadgroupSize: MTLSize! = nil
    private var threadgroupCount: MTLSize! = nil
    
    // Uniforms
    var parameter = PieceParameter(delta: float4(), time: float4())
    var modelMatrix = float4x4(matrix_identity_float4x4)
    private var isStarted = false
    
    func setup(url: NSURL) -> Bool {
        let device = Render.current.device
        let mtkView = Render.current.mtkView
        let library = Render.current.library
        
        /* render */
        guard let vertex_pg = library.newFunctionWithName("imageBoardVertex") else { return false }
        guard let fragment_pg = library.newFunctionWithName("imageBoardFragment") else { return false }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "ImageBoardPipeLine"
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.vertexFunction = vertex_pg
        pipelineDescriptor.fragmentFunction = fragment_pg
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        pipelineDescriptor.alphaToCoverageEnabled = true
        do {
            pipelineState = try device.newRenderPipelineStateWithDescriptor(pipelineDescriptor)
        } catch {
            return false
        }
        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .Less
        depthDescriptor.depthWriteEnabled = true
        depthState = device.newDepthStencilStateWithDescriptor(depthDescriptor)
        
        frameUniformBuffer = device.newBufferWithLength(sizeof(float4x4), options: .CPUCacheModeDefaultCache)
        
        // テクスチャをロード
        let loader = MTKTextureLoader(device: device)
        do {
            imageTexture = try loader.newTextureWithContentsOfURL(url, options: nil)
        } catch let error as NSError {
            print(error.debugDescription)
            return false
        }
        renderBuffer = device.newBufferWithLength(sizeof(ImagePiece) * imageTexture.width * imageTexture.height,
            options: .CPUCacheModeDefaultCache)
        
        /* compute */
        guard let pg_setup = library.newFunctionWithName("fallImageSetup") else { return false }
        guard let pg = library.newFunctionWithName("fallImageCompute") else { return false }
        do {
            setupComputeState = try device.newComputePipelineStateWithFunction(pg_setup)
            computeState = try device.newComputePipelineStateWithFunction(pg)
        } catch {
            return false
        }
        activeComputeState = setupComputeState
     
        parameterBuffer = device.newBufferWithLength(sizeof(PieceParameter), options: .CPUCacheModeDefaultCache)
        
        // スレッド数は32の倍数（64-192）
        threadgroupSize = MTLSize(width: imageTexture.width, height: imageTexture.height, depth: 1)
        threadgroupCount = MTLSize(width: 1, height: 1, depth: 1)
        
        // パラメータの設定
        parameter.delta.x = 0
        parameter.delta.y = FallSpeed
        parameter.delta.z = 0
        parameter.delta.w = FallTarget      // 落下地点
        parameter.time.x = 0
        parameter.time.w = FallDelay        // y方向のdelay

        return true
    }
    
    func update() {
        let ren = Render.current
        
        let p = UnsafeMutablePointer<float4x4>(frameUniformBuffer.contents())
        let mat = ren.projectionMatrix * ren.cameraMatrix * modelMatrix
        p.memory = mat
    }
    
    func render(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.pushDebugGroup("Particle")
        
        // Set context state.
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setCullMode(.None)
        
        // Set the our per frame uniforms.
        renderEncoder.setVertexBuffer(renderBuffer, offset: 0, atIndex: VertexAttribute.Piece.index())
        renderEncoder.setVertexBuffer(frameUniformBuffer, offset: 0, atIndex: VertexAttribute.Uniform.index())
        renderEncoder.drawPrimitives(.Point, vertexStart: 0, vertexCount: imageTexture.width * imageTexture.height)
        
        renderEncoder.popDebugGroup()
    }
    
    func compute(commandBuffer: MTLCommandBuffer) {
        // 前回実行時からの経過時間を設定
        let dt = Float(Render.current.deltaTime)
        parameter.time.x += dt
        parameter.time.y = dt
        let p = UnsafeMutablePointer<PieceParameter>(parameterBuffer.contents())
        p.memory = parameter
        
        let computeEncoder = commandBuffer.computeCommandEncoder()
        
        computeEncoder.setComputePipelineState(activeComputeState)
        computeEncoder.setBuffer(renderBuffer, offset: 0, atIndex: ComputeBuffer.Piece.index())
        computeEncoder.setBuffer(parameterBuffer, offset: 0, atIndex: ComputeBuffer.Parameter.index())
        computeEncoder.setTexture(imageTexture, atIndex: TextureType.Image.index())
        computeEncoder.dispatchThreadgroups(threadgroupSize, threadsPerThreadgroup: threadgroupCount)
        computeEncoder.endEncoding()
    }
    
    func postRender() {
        // 一定時間経過すれば最初からスタート
        if parameter.time.x > TotalLoopTime {
            activeComputeState = setupComputeState
            parameter.time.x = 0
        } else {
            activeComputeState = computeState
        }
    }
}

