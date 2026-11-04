#include "spirv_msl.hpp"
#include <cassert>
#include <cstring>
#include <iostream>
#include <vector>

// Self-authored minimal SPIR-V, not a redistributed shaderpack or user capture.
static void instruction(std::vector<uint32_t> &words, unsigned op, std::initializer_list<uint32_t> args) {
    words.push_back(((args.size()+1)<<16)|op);
    words.insert(words.end(), args.begin(), args.end());
}
static std::vector<uint32_t> vertex(unsigned component) {
    std::vector<uint32_t> w{0x07230203,0x00010000,0,17,0};
    instruction(w,17,{1});                         // Shader capability
    instruction(w,14,{0,1});                      // Logical, GLSL450
    instruction(w,15,{0,12,0x6e69616d,0,10,11});  // vertex main, interfaces
    instruction(w,71,{10,30,0});                 // input Location 0
    instruction(w,71,{10,31,component});          // input Component
    instruction(w,71,{11,11,0});                 // output BuiltIn Position
    instruction(w,19,{1});                       // void
    instruction(w,33,{2,1});                     // function -> void
    instruction(w,21,{3,32,1});                  // signed int32
    instruction(w,22,{4,32});                    // float32
    instruction(w,23,{5,4,4});                   // float4
    instruction(w,32,{6,1,3});                   // ptr Input int32
    instruction(w,32,{7,3,5});                   // ptr Output float4
    instruction(w,43,{4,8,0});                   // float zero
    instruction(w,43,{4,9,0x3f800000});          // float one
    instruction(w,59,{6,10,1});                  // input variable
    instruction(w,59,{7,11,3});                  // output variable
    instruction(w,54,{1,12,0,2});                // function
    instruction(w,248,{13});
    instruction(w,61,{3,14,10});                 // load input int
    instruction(w,111,{4,15,14});                // convert signed integer to float
    instruction(w,80,{5,16,15,8,8,9});           // float4(value,0,0,1)
    instruction(w,62,{11,16});
    instruction(w,253,{});
    instruction(w,56,{});
    return w;
}
int main(int argc, char **argv) {
    assert(argc==2);
    bool expect_fixed=!std::strcmp(argv[1],"fixed");
    for(unsigned component:{1u,2u}) {
        spirv_cross::CompilerMSL compiler(vertex(component));
        auto options=compiler.get_msl_options();
        options.platform=spirv_cross::CompilerMSL::Options::iOS;
        options.set_msl_version(2,2);
        compiler.set_msl_options(options);
        // Exactly the component-zero hint MoltenVK 1.2.9 supplies for UINT16.
        spirv_cross::MSLShaderInterfaceVariable hint;
        hint.location=0;hint.format=spirv_cross::MSL_SHADER_VARIABLE_FORMAT_UINT16;
        compiler.add_msl_shader_input(hint);
        std::string msl=compiler.compile();
        std::string physical=std::string(expect_fixed?"uint":"int")+std::to_string(component+1)+" m_location_0 [[attribute(0)]]";
        assert(msl.find(physical)!=std::string::npos);
        // Logical body must remain signed; unsigned physical fetch still holds
        // all 16-bit entity IDs as positive int32 values, including 50084.
        assert(msl.find("int ")!=std::string::npos);
        for(uint32_t id:{0u,32767u,32768u,50084u,65535u})
            assert(static_cast<int32_t>(id)==static_cast<int32_t>(static_cast<uint16_t>(id)));
    }
    std::cout<<(expect_fixed?"PASS: packed UINT16 vertex inputs use unsigned physical fetch without changing logical IDs\n":
                             "PASS: unpatched SPIRV-Cross reproduces signed packed vertex inputs\n");
}
