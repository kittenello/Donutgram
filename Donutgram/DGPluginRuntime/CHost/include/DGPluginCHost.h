#ifndef DG_PLUGIN_HOST_H
#define DG_PLUGIN_HOST_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct DGJSHost DGJSHost;
typedef void (*DGJSRequest)(void *, int64_t request_id, const char *json);
DGJSHost *dgjs_create(DGJSRequest request, void *opaque);
int dgjs_add_file(DGJSHost *, const char *, const uint8_t *, size_t);
int dgjs_start(DGJSHost *, const char *entry, const char *bootstrap, const char *environment);
int dgjs_dispatch(DGJSHost *, const char *kind, const char *payload);
int dgjs_pump(DGJSHost *);
int dgjs_reply(DGJSHost *, int64_t request_id, const char *json);
void dgjs_stop(DGJSHost *);
void dgjs_destroy(DGJSHost *);
const char *dgjs_error(DGJSHost *);
/* After a dispatch completes (status 0): the sanitized error code if its promise was rejected, else NULL.
   A rejected dispatch does not stop the runtime; only module, activation, budget and memory failures do. */
const char *dgjs_rejection(DGJSHost *);
#ifdef __cplusplus
}
#endif
#endif
