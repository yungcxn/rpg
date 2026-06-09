
#define GLFW_INCLUDE_VULKAN
#define GLFW_EXPOSE_NATIVE_X11

#include <GLFW/glfw3.h>
#include <stdio.h> // TODO, only for printf? seriously? bad practice

// https://vulkan-tutorial.com/Drawing_a_triangle/Setup/Validation_layers
static VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT messageType,
    const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
    void* pUserData
) {
    fprintf(stderr, "validation layer: %s\n", pCallbackData->pMessage);
    return VK_FALSE;
}