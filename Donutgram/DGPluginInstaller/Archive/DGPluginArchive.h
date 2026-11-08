#ifndef DG_PLUGIN_ARCHIVE_H
#define DG_PLUGIN_ARCHIVE_H
#include <stddef.h>
#include <stdint.h>
int dg_plugin_inflate(const uint8_t *input, size_t input_size, uint8_t *output, size_t output_size);
uint32_t dg_plugin_crc32(const uint8_t *input, size_t size);
#if defined(_WIN32)
int dg_plugin_sha256(const uint8_t *input, size_t size, uint8_t output[32]);
#endif
#endif
