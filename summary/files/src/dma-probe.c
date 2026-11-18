#include <fcntl.h>
#include <inttypes.h>
#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include "dma_buf_phys.h"

static int error(const char *step)
{
    perror(step);
    return 1;
}

int main(void)
{
    const size_t size = 4096;
    int heap = open("/dev/dma_heap/carveout_vision_apps_shared-memories", O_RDONLY | O_CLOEXEC);
    if (heap < 0) return error("open heap");
    struct dma_heap_allocation_data alloc = {.len = size, .fd_flags = O_RDWR | O_CLOEXEC};
    if (ioctl(heap, DMA_HEAP_IOCTL_ALLOC, &alloc)) return error("heap allocation");
    close(heap);
    int remote = open("/dev/remoteproc0", O_RDONLY | O_CLOEXEC);
    if (remote < 0) return error("open SDK address-query device");
    struct dma_buf_phys_data phys = {.fd = alloc.fd};
    if (ioctl(remote, RPROC_IOC_DMA_BUF_ATTACH, &phys)) return error("TI DMA-BUF address ioctl");
    if (phys.phys < 0xb8000000ULL || phys.phys > 0xd8000000ULL-size || phys.phys % size) {
        fprintf(stderr, "Address outside expected SDK heap or misaligned\n");
        return 1;
    }
    unsigned char *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, alloc.fd, 0);
    if (p == MAP_FAILED) return error("mmap");
    struct dma_buf_sync sync = {.flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_RW};
    if (ioctl(alloc.fd, DMA_BUF_IOCTL_SYNC, &sync)) return error("sync start");
    memset(p, 0x5a, size);
    sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_RW;
    if (ioctl(alloc.fd, DMA_BUF_IOCTL_SYNC, &sync)) return error("sync end");
    munmap(p, size);
    close(remote);
    close(alloc.fd);
    printf("DMA_HOST_OK phys=%#" PRIx64 "\n", (uint64_t)phys.phys);
}
