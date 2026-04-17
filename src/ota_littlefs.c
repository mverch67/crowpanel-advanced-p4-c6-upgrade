/*
 * SPDX-FileCopyrightText: 2025-2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>

#include "esp_app_desc.h"
#include "esp_app_format.h"
#include "esp_err.h"
#include "esp_hosted.h"
#include "esp_hosted_api_types.h"
#include "esp_hosted_ota.h"
#include "esp_littlefs.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "ota_littlefs";

#ifndef CHUNK_SIZE
#define CHUNK_SIZE 1500
#endif

static esp_err_t parse_image_header_from_file(const char *file_path, size_t *firmware_size,
                                              char *app_version_str, size_t version_str_len)
{
    FILE *file;
    esp_image_header_t image_header;
    esp_image_segment_header_t segment_header;
    esp_app_desc_t app_desc;
    size_t offset = 0;
    size_t total_size = 0;

    file = fopen(file_path, "rb");
    if (file == NULL) {
        ESP_LOGE(TAG, "Failed to open firmware file for header verification: %s", file_path);
        return ESP_FAIL;
    }

    if (fread(&image_header, sizeof(image_header), 1, file) != 1) {
        ESP_LOGE(TAG, "Failed to read image header from file");
        fclose(file);
        return ESP_FAIL;
    }

    if (image_header.magic != ESP_IMAGE_HEADER_MAGIC) {
        ESP_LOGE(TAG, "Invalid image magic: 0x%" PRIx8 " (expected: 0x%" PRIx8 ")",
                 image_header.magic, ESP_IMAGE_HEADER_MAGIC);
        fclose(file);
        return ESP_ERR_INVALID_ARG;
    }

    offset = sizeof(image_header);
    total_size = sizeof(image_header);

    for (int index = 0; index < image_header.segment_count; index++) {
        if (fseek(file, offset, SEEK_SET) != 0 ||
            fread(&segment_header, sizeof(segment_header), 1, file) != 1) {
            ESP_LOGE(TAG, "Failed to read segment %d header", index);
            fclose(file);
            return ESP_FAIL;
        }

        total_size += sizeof(segment_header) + segment_header.data_len;
        offset += sizeof(segment_header) + segment_header.data_len;

        if (index == 0) {
            size_t app_desc_offset = sizeof(image_header) + sizeof(segment_header);
            if (fseek(file, app_desc_offset, SEEK_SET) == 0 &&
                fread(&app_desc, sizeof(app_desc), 1, file) == 1) {
                strncpy(app_version_str, app_desc.version, version_str_len - 1);
                app_version_str[version_str_len - 1] = '\0';
            } else {
                strncpy(app_version_str, "unknown", version_str_len - 1);
                app_version_str[version_str_len - 1] = '\0';
            }
        }
    }

    total_size += (16 - (total_size % 16)) % 16;
    total_size += 1;
    if (image_header.hash_appended == 1) {
        total_size += 32;
    }

    *firmware_size = total_size;
    fclose(file);
    return ESP_OK;
}

static esp_err_t find_latest_firmware(char *firmware_path, size_t max_len)
{
    DIR *dir;
    struct dirent *entry;
    struct stat file_stat;
    char *latest_file = malloc(256);
    char *full_path = malloc(512);

    if (!latest_file || !full_path) {
        free(latest_file);
        free(full_path);
        return ESP_ERR_NO_MEM;
    }

    memset(latest_file, 0, 256);
    dir = opendir("/littlefs");
    if (dir == NULL) {
        free(latest_file);
        free(full_path);
        return ESP_FAIL;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (strstr(entry->d_name, ".bin") != NULL) {
            snprintf(full_path, 512, "/littlefs/%s", entry->d_name);
            if (stat(full_path, &file_stat) == 0) {
                strncpy(latest_file, entry->d_name, 255);
                latest_file[255] = '\0';
                break;
            }
        }
    }
    closedir(dir);

    if (strlen(latest_file) == 0) {
        free(latest_file);
        free(full_path);
        return ESP_FAIL;
    }

    if (snprintf(firmware_path, max_len, "/littlefs/%s", latest_file) >= (int)max_len) {
        free(latest_file);
        free(full_path);
        return ESP_FAIL;
    }

    free(latest_file);
    free(full_path);
    return ESP_OK;
}

static esp_err_t check_littlefs_files(void)
{
    DIR *dir;
    struct dirent *entry;
    int file_count = 0;

    dir = opendir("/littlefs");
    if (dir == NULL) {
        return ESP_FAIL;
    }

    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        file_count++;
    }
    closedir(dir);

    if (file_count == 0) {
        return ESP_ERR_NOT_FOUND;
    }

    return ESP_OK;
}

esp_err_t ota_littlefs_perform(bool delete_after_use)
{
    char *firmware_path = malloc(256);
    FILE *firmware_file;
    uint8_t *chunk = malloc(CHUNK_SIZE);
    size_t bytes_read;
    esp_err_t ret = ESP_OK;

    if (!firmware_path || !chunk) {
        free(firmware_path);
        free(chunk);
        return ESP_ERR_NO_MEM;
    }

    esp_vfs_littlefs_conf_t conf = {
        .base_path = "/littlefs",
        .partition_label = "storage",
        .format_if_mount_failed = true,
        .dont_mount = false,
    };

    ret = esp_vfs_littlefs_register(&conf);
    if (ret != ESP_OK) {
        free(firmware_path);
        free(chunk);
        return ESP_HOSTED_SLAVE_OTA_FAILED;
    }

    ret = check_littlefs_files();
    if (ret != ESP_OK) {
        esp_vfs_littlefs_unregister("storage");
        free(firmware_path);
        free(chunk);
        return ESP_HOSTED_SLAVE_OTA_FAILED;
    }

    ret = find_latest_firmware(firmware_path, 256);
    if (ret != ESP_OK) {
        esp_vfs_littlefs_unregister("storage");
        free(firmware_path);
        free(chunk);
        return ESP_HOSTED_SLAVE_OTA_FAILED;
    }

    size_t firmware_size;
    char new_app_version[32];
    ret = parse_image_header_from_file(firmware_path, &firmware_size, new_app_version, sizeof(new_app_version));
    if (ret != ESP_OK) {
        esp_vfs_littlefs_unregister("storage");
        free(firmware_path);
        free(chunk);
        return ESP_HOSTED_SLAVE_OTA_FAILED;
    }

#ifdef CONFIG_OTA_VERSION_CHECK_SLAVEFW_SLAVE
    esp_hosted_coprocessor_fwver_t current_slave_version = {0};
    esp_err_t version_ret = esp_hosted_get_coprocessor_fwversion(&current_slave_version);

    if (version_ret == ESP_OK) {
        char current_version_str[32];
        snprintf(current_version_str, sizeof(current_version_str), "%" PRIu32 ".%" PRIu32 ".%" PRIu32,
                 current_slave_version.major1, current_slave_version.minor1, current_slave_version.patch1);
        if (strcmp(new_app_version, current_version_str) == 0) {
            esp_vfs_littlefs_unregister("storage");
            free(firmware_path);
            free(chunk);
            return ESP_HOSTED_SLAVE_OTA_NOT_REQUIRED;
        }
    }
#endif

    firmware_file = fopen(firmware_path, "rb");
    if (firmware_file == NULL) {
        esp_vfs_littlefs_unregister("storage");
        free(firmware_path);
        free(chunk);
        return ESP_FAIL;
    }

    ret = esp_hosted_slave_ota_begin();
    if (ret != ESP_OK) {
        fclose(firmware_file);
        esp_vfs_littlefs_unregister("storage");
        free(firmware_path);
        free(chunk);
        return ESP_HOSTED_SLAVE_OTA_FAILED;
    }

    while ((bytes_read = fread(chunk, 1, CHUNK_SIZE, firmware_file)) > 0) {
        ret = esp_hosted_slave_ota_write(chunk, bytes_read);
        if (ret != ESP_OK) {
            fclose(firmware_file);
            esp_vfs_littlefs_unregister("storage");
            free(firmware_path);
            free(chunk);
            return ESP_HOSTED_SLAVE_OTA_FAILED;
        }
    }

    fclose(firmware_file);

    ret = esp_hosted_slave_ota_end();
    if (ret != ESP_OK) {
        esp_vfs_littlefs_unregister("storage");
        free(firmware_path);
        free(chunk);
        return ESP_HOSTED_SLAVE_OTA_FAILED;
    }

    if (delete_after_use) {
        unlink(firmware_path);
    }

    esp_vfs_littlefs_unregister("storage");
    free(firmware_path);
    free(chunk);
    return ESP_HOSTED_SLAVE_OTA_COMPLETED;
}