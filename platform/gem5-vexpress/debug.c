/*
 * Copyright (c) 2026 Cache55
 *
 * Use of this source code is governed by a MIT-style
 * license that can be found in the LICENSE file or at
 * https://opensource.org/licenses/MIT
 */
#include <dev/uart.h>
#include <platform/debug.h>
#include <target/debugconfig.h>

/* DEBUG_UART must be defined to 0: gem5's VExpress has its console on UART0 */
#if !defined(DEBUG_UART) || DEBUG_UART != 0
#error define DEBUG_UART to 0
#endif

void platform_dputc(char c) {
    if (c == '\n')
        uart_putc(DEBUG_UART, '\r');
    uart_putc(DEBUG_UART, c);
}

int platform_dgetc(char *c, bool wait) {
    int ret = uart_getc(DEBUG_UART, wait);
    if (ret < 0)
        return ret;
    *c = ret;
    return 0;
}

void platform_pputc(char c) {
    if (c == '\n')
        uart_pputc(DEBUG_UART, '\r');
    uart_pputc(DEBUG_UART, c);
}

int platform_pgetc(char *c, bool wait) {
    int ret = uart_pgetc(DEBUG_UART);
    if (ret < 0)
        return ret;
    *c = ret;
    return 0;
}
