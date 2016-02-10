//
//  ImageBoard.metal
//  MetalImage
//
//  Created by M.Ike on 2016/02/05.
//  Copyright © 2016年 M.Ike. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;


struct PieceParameter {
    float4      delta;
    float4      time;
};

struct ImagePiece {
    float4      position;
    float4      color;
    float4      acc;            // delta_x, delta_y, delta_z, delay
};

struct VertexOutput {
    float4      position        [[ position ]];
    float4      color;
    float       pointSize       [[ point_size ]];
};

struct FragOutput {
    float4      color;
};


static uint xorshift32(const uint state) {
    uint value = state;
    value = value ^ (value << 13);
    value = value ^ (value >> 17);
    value = value ^ (value << 5);
    return value;
}


// 滝のように下からdelayをかけて落ちていくタイプ
// パラメータ
//  delta.xyz : 各軸の移動量
//  delta.w : 落下地点
//  time.x : スタートからの経過時間
//  time.y : 前フレームからの経過時間
//  time.z : -
//  time.w : y方向のdelay
kernel void fallImageSetup(device ImagePiece* particles [[ buffer(0) ]],
                           constant PieceParameter& param [[ buffer(1) ]],
                           texture2d<float, access::read> image [[ texture(0) ]],
                           uint2 id [[ thread_position_in_grid ]],
                           uint2 size [[ threads_per_grid ]]) {
    uint index = id.x + id.y * size.x;
    particles[index].position = float4(id.x / (float)size.x, id.y / (float)size.y, 0, 1);
    particles[index].color = image.read(id);
    
    // 乱数の算出
    threadgroup uint rnd = 2463534242;
    rnd = xorshift32(rotate(rnd, id.x));
    float rnd_d = param.time.w * (1 - (float)rnd / UINT_MAX * 0.1);
    
    particles[index].acc = float4(param.delta.x, param.delta.y, param.delta.z, rnd_d * id.y);
}

kernel void fallImageCompute(device ImagePiece* particles [[ buffer(0) ]],
                             constant PieceParameter& param [[ buffer(1) ]],
                             texture2d<float, access::read> image [[ texture(0) ]],
                             uint2 id [[ thread_position_in_grid ]],
                             uint2 size [[ threads_per_grid ]]) {
    uint index = id.x + id.y * size.x;

    // 乱数の算出
    threadgroup uint rnd = 2463534242;
    rnd = xorshift32(rotate(rnd, id.x));
    float rnd_d = 1 - (float)rnd / UINT_MAX * 0.1;

    // 時間を補正
    float t = fmax(0.f, param.time.x - particles[index].acc.w) * param.time.y * rnd_d;
    
    particles[index].position += t * particles[index].acc;
    particles[index].position.w = 1;
    
    // 落下地点を超えていればαを減算
    float4 f = step(param.delta.w, particles[index].position + t * particles[index].acc);
    particles[index].color.a -= (1 - f.x * f.y * f.z) * 0.1 * rnd_d * 3;
}


vertex VertexOutput imageBoardVertex(device ImagePiece* posData [[ buffer(0) ]],
                                     constant float4x4& mvp [[ buffer(1) ]],
                                     uint vid [[ vertex_id ]]) {
    VertexOutput output;
    
    float4 position = posData[vid].position;
    output.position = mvp * position;
    output.pointSize = 10 / output.position.w;
    output.color = posData[vid].color;
    
    return output;
}

fragment FragOutput imageBoardFragment(VertexOutput in [[ stage_in ]],
                                       float4 color [[ color(0) ]]) {
    // ほぼ見えない場合はピクセルを破棄
    if (in.color.a < 0.1) discard_fragment();
    FragOutput output;
    output.color.rgb = color.rgb + in.color.rgb;
    output.color.a = in.color.a;
    return output;
}
