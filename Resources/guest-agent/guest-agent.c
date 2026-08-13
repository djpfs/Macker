//===----------------------------------------------------------------------===//
// guest-agent.c — minimal Linux guest agent for the hot-reload bridge.
//
// virtiofs does not propagate inotify events into the guest, so watch tools
// (Vite, webpack, nodemon, Air) never see host-side edits. This agent closes
// the gap: it listens on a TCP port, reads container-relative paths (one per
// line), and `touch`es each one. The Linux kernel then emits inotify ATTRIB,
// which is exactly what watch tools listen for.
//
// Build (from the repo root):
//   ./Scripts/build-guest-agent.sh
//
// The result is a static aarch64 binary (~20KB) at Resources/guest-agent.
//===----------------------------------------------------------------------===//

#include <arpa/inet.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>

#define MAX_LINE 4096

// Touch a path by updating its mtime. Returns 0 on success.
static int touch_path(const char *path) {
    struct utimbuf times;
    times.actime = time(NULL);
    times.modtime = time(NULL);
    return utime(path, &times);
}

// Read paths (one per line) from the client, touch each, then ack.
static void handle_client(int fd) {
    char line[MAX_LINE];
    size_t pos = 0;
    for (;;) {
        char c;
        ssize_t n = read(fd, &c, 1);
        if (n <= 0) break;
        if (c == '\n') {
            line[pos] = '\0';
            if (pos == 0) break; // empty line ends the batch
            touch_path(line);
            pos = 0;
        } else if (pos + 1 < MAX_LINE) {
            line[pos++] = c;
        }
    }
    write(fd, "ok\n", 3);
    close(fd);
}

int main(int argc, char **argv) {
    int port = 9000;
    if (argc > 1) port = atoi(argv[1]);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("socket");
        return 1;
    }
    int one = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons((uint16_t)port);

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }
    if (listen(sock, 16) < 0) {
        perror("listen");
        return 1;
    }

    for (;;) {
        int client = accept(sock, NULL, NULL);
        if (client < 0) continue;
        handle_client(client);
    }
}
