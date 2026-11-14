#include "DGPluginArchive.h"
#include <limits.h>
#include <string.h>
#include <zlib.h>
#if defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>
#endif

int dg_plugin_inflate(const uint8_t *input, size_t input_size, uint8_t *output, size_t output_size) {
    if (input_size > UINT_MAX || output_size > UINT_MAX) return 0;
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_size;
    stream.next_out = output;
    stream.avail_out = output_size ? (uInt)output_size : 1;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return 0;
    int result = inflate(&stream, Z_FINISH);
    int valid = result == Z_STREAM_END && stream.total_in == input_size && stream.total_out == output_size;
    inflateEnd(&stream);
    return valid;
}

uint32_t dg_plugin_crc32(const uint8_t *input, size_t size) {
    if (size > UINT_MAX) return 0;
    return (uint32_t)crc32(0, input, (uInt)size);
}

#if defined(_WIN32)
int dg_plugin_sha256(const uint8_t *input, size_t size, uint8_t output[32]) {
    if (size > ULONG_MAX || !output || (!input && size)) return 0;
    const uint8_t empty = 0;
    if (!input) input = &empty;
    NTSTATUS result = BCryptHash(BCRYPT_SHA256_ALG_HANDLE, NULL, 0, (PUCHAR)input, (ULONG)size, output, 32);
    return result >= 0;
}
#endif
