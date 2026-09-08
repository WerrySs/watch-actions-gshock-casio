#ifndef WATCHBRIDGE_CORE_H
#define WATCHBRIDGE_CORE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct WbBytes {
    uint8_t *data;
    size_t len;
    size_t capacity;
} WbBytes;

const char *wb_core_version(void);
char *wb_keyboard_catalog_json(void);
void wb_string_free(char *value);
void wb_bytes_free(WbBytes value);
char *wb_normalize_model(const char *value);
char *wb_model_from_bluetooth_name(const char *value);
bool wb_is_supported_model(const char *value);
bool wb_is_supported_bluetooth_name(const char *value);
char *wb_sanitize_text(const char *value, size_t maximum_characters);
char *wb_validate_app_data_json(const char *value);
uint8_t wb_decode_button(const uint8_t *data, size_t len);
bool wb_decode_condition(
    const uint8_t *data,
    size_t len,
    uint8_t *battery_percent,
    int16_t *temperature_celsius
);
WbBytes wb_encode_time(int64_t unix_seconds, int32_t offset_seconds);

#endif
