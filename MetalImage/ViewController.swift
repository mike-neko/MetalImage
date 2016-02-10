//
//  ViewController.swift
//  MetalImage
//
//  Created by M.Ike on 2016/02/03.
//  Copyright © 2015年 M.Ike. All rights reserved.
//

import UIKit
import MetalKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        // Metalの初期設定
        setup_metal()
        // 描画するものの初期設定
        load_assets()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: -
    private func setup_metal() {
        if let mtkView = Render.current.setupView(self.view as? MTKView) {
            /* MTKViewの初期設定 */
            mtkView.sampleCount = 1
            mtkView.depthStencilPixelFormat = .Invalid
            
            mtkView.colorPixelFormat = .BGRA8Unorm
            mtkView.clearColor = MTLClearColorMake(0.1, 0.1, 0.1, 1)
            
            // compute shader利用時はfalse
            mtkView.framebufferOnly = false
        } else {
            assert(false)
        }
    }
    
    private func load_assets() {
        // カメラ位置を調整
        Render.current.cameraMatrix = Matrix.lookAt(camera: float3(0, 0, 8), target: float3(0, 0, 0), up: float3(0, 1, 0))
        
        let img = ImageBoard()
        img.setup(NSBundle.mainBundle().URLForResource("Assets/sample", withExtension: "jpg")!)
        img.modelMatrix = Matrix.translation(x: 0.5, y: 0, z: 0) * Matrix.scale(x: -1, y: -1, z: 1)
        Render.current.computeTargets.append(img)
        Render.current.renderTargets.append(img)
    }
}

