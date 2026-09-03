#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <new>

namespace
{
    std::size_t allocations = 0;
}

void *operator new(std::size_t size)
{
    if (void *value = std::malloc(size))
    {
        ++allocations;
        return value;
    }
    throw std::bad_alloc();
}

void operator delete(void *value) noexcept
{
    if (value != nullptr)
    {
        --allocations;
        std::free(value);
    }
}

void operator delete(void *value, std::size_t) noexcept
{
    operator delete(value);
}

#include "../libfastdev_quickjs_runtime.cpp"

void *returnValue(JSContext *ctx, size_t type, void *)
{
    if (type == JSChannelType_METHON)
        return new JSValue(JS_NewInt32(ctx, 42));
    return nullptr;
}

int main()
{
    JSRuntime *runtime = jsNewRuntime(returnValue, 0);
    JSContext *context = jsNewContext(runtime);
    const std::size_t channelBaseline = allocations;

    for (int i = 0; i < 128; ++i)
    {
        JSValue value = js_channel(context, JS_UNDEFINED, 0, nullptr, 0, nullptr);
        JS_FreeValue(context, value);
    }
    if (allocations != channelBaseline)
    {
        std::fprintf(
            stderr, "channel wrappers: %zu -> %zu\n", channelBaseline, allocations);
        return 1;
    }

    JSValue *object = jsNewObject(context);
    JSValue *property = jsNewInt64(context, 42);
    JSAtom atom = JS_NewAtom(context, "answer");
    const std::size_t propertyBaseline = allocations;
    const int result = jsDefinePropertyValue(
        context, object, atom, property, JS_PROP_C_W_E);
    if (result < 0 || allocations != propertyBaseline - 1)
    {
        std::fprintf(
            stderr, "property wrappers: %zu -> %zu\n", propertyBaseline, allocations);
        return 2;
    }

    jsFreeAtom(context, atom);
    jsFreeValue(context, object, 1);
    jsFreeContext(context);
    jsFreeRuntime(runtime);
    return 0;
}
