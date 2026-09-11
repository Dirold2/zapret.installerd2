#!/bin/bash

product_health() {
    service_is_active "$PRODUCT_SERVICE" ||
        pgrep -x "$PRODUCT_BIN_NAME" >/dev/null 2>&1
}
