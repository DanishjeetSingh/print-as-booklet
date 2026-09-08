// Decode the Swift encoder's output using macOS's independent CUPS implementation.
#include <cups/raster.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) return 2;
    cups_raster_t *r = cupsRasterOpen(fd, CUPS_RASTER_READ);
    cups_page_header2_t h;
    unsigned pages = 0;
    while (cupsRasterReadHeader2(r, &h)) {
        if (h.cupsWidth != 2550 || h.cupsHeight != 3300 || h.cupsBytesPerLine != 2550 || h.Duplex != 1 || h.Tumble != 1 || h.cupsColorSpace != 18) return 3;
        unsigned char *row = malloc(h.cupsBytesPerLine);
        if (!row) return 4;
        for (unsigned y = 0; y < h.cupsHeight; y++) {
            if (cupsRasterReadPixels(r, row, h.cupsBytesPerLine) != h.cupsBytesPerLine) return 5;
        }
        free(row); pages++;
    }
    cupsRasterClose(r); close(fd);
    if (pages != 1) return 6;
    printf("PASS CUPS independently decoded %u Letter raster page at 300 dpi, short-edge duplex\n", pages);
    return 0;
}
