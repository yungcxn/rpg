const std = @import("std");
const c = @import("c_vk_glfw");
const util = @import("util.zig");
const req_vksuc = util.req_vksuc;
const ZVkError = util.ZVkError;

const vert_spv align(@alignOf(u32)) = @embedFile("vertex_shader").*;
const frag_spv align(@alignOf(u32)) = @embedFile("fragment_shader").*;

pipeline_layout: c.VkPipelineLayout,
pipeline: c.VkPipeline,
device: c.VkDevice,

pub fn init(
    device: c.VkDevice,
    sc_extent: c.VkExtent2D,
    img_format: c.VkFormat,
) ZVkError!@This() {
    const vert_module = try create_shader_mod(device, &vert_spv);
    defer c.vkDestroyShaderModule(device, vert_module, null);
    const frag_module = try create_shader_mod(device, &frag_spv);
    defer c.vkDestroyShaderModule(device, frag_module, null);

    const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
            .module = vert_module,
            .pName = "main", // matches `export fn main()` in vertex-zig-file
            .pSpecializationInfo = null,
        },
        .{
            .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = frag_module,
            .pName = "main", // same for fragment-zig-file
            .pSpecializationInfo = null,
        },
    };

    const vertex_ii = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    };

    const in_asm = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(sc_extent.width),
        .height = @floatFromInt(sc_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    const scissor = c.VkRect2D{
        .offset = c.VkOffset2D{ .x = 0, .y = 0 },
        .extent = sc_extent,
    };

    const dyn_states = [_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };
    const dyn_state_ci = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = @intCast(dyn_states.len),
        .pDynamicStates = &dyn_states,
    };

    const viewport_state = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .pViewports = &viewport,
        .scissorCount = 1,
        .pScissors = &scissor,
    };

    const rasterizer = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .lineWidth = 1.0,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
    };

    const multisampling = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .sampleShadingEnable = c.VK_FALSE,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
    };

    const color_blend_attachment = c.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT |
            c.VK_COLOR_COMPONENT_G_BIT |
            c.VK_COLOR_COMPONENT_B_BIT |
            c.VK_COLOR_COMPONENT_A_BIT,
        .blendEnable = c.VK_TRUE,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
    };

    const color_blending = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment,
    };

    const pipeline_layout_ci = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
    };
    var pipeline_layout: c.VkPipelineLayout = null;
    try req_vksuc(
        c.vkCreatePipelineLayout(device, &pipeline_layout_ci, null, &pipeline_layout),
    );
    errdefer c.vkDestroyPipelineLayout(device, pipeline_layout, null);

    const pipeline_render_ci = c.VkPipelineRenderingCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = &img_format,
    };

    const pipeline_ci = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &pipeline_render_ci,
        .stageCount = @intCast(shader_stages.len),
        .pStages = &shader_stages,
        .pVertexInputState = &vertex_ii,
        .pInputAssemblyState = &in_asm,
        .pViewportState = &viewport_state,
        .pRasterizationState = &rasterizer,
        .pMultisampleState = &multisampling,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blending,
        .pDynamicState = &dyn_state_ci,
        .layout = pipeline_layout,
        .renderPass = null,
        .basePipelineHandle = null,
        .basePipelineIndex = -1,
        .subpass = 0,
    };

    var graphics_pipeline: c.VkPipeline = null;
    try req_vksuc(
        c.vkCreateGraphicsPipelines(device, null, 1, &pipeline_ci, null, &graphics_pipeline),
    );

    return @This(){
        .pipeline_layout = pipeline_layout,
        .pipeline = graphics_pipeline,
        .device = device,
    };
}

pub fn deinit(self: @This()) void {
    c.vkDestroyPipeline(self.device, self.pipeline, null);
    c.vkDestroyPipelineLayout(self.device, self.pipeline_layout, null);
}

fn create_shader_mod(
    device: c.VkDevice,
    spv: []const u8,
) ZVkError!c.VkShaderModule {
    const create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv.ptr)),
    };

    var shader_module: c.VkShaderModule = undefined;
    try req_vksuc(
        c.vkCreateShaderModule(device, &create_info, null, &shader_module),
    );
    return shader_module;
}
