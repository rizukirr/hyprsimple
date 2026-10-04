import QtQuick
import Quickshell.Io

// CPU, memory and GPU usage. CPU and memory are read from /proc every few seconds.
// The GPU is only polled while watchGpu is set, because asking nvidia-smi wakes a
// sleeping laptop GPU and keeps it awake.
// vibekit: GPU numbers come from nvidia-smi only, read /sys/class/drm/card*/device/gpu_busy_percent to cover AMD
Item {
    id: root

    property bool watchGpu: false
    property int intervalMs: 2000

    // Fractions from 0 to 1.
    property real cpu: 0
    property real memory: 0
    property real memoryUsedGiB: 0
    property real memoryTotalGiB: 0
    // null until nvidia-smi has answered, and on machines without it.
    property var gpu: null

    property real lastIdle: 0
    property real lastTotal: 0

    function readMemory(text) {
        const total = Number(/MemTotal:\s+(\d+)/.exec(text)?.[1] ?? 0)
        const available = Number(/MemAvailable:\s+(\d+)/.exec(text)?.[1] ?? 0)
        if (total === 0) return
        memory = (total - available) / total
        memoryUsedGiB = (total - available) / 1048576
        memoryTotalGiB = total / 1048576
    }

    // First line of /proc/stat: cumulative jiffies per state. Usage is the share of
    // non-idle time since the previous reading.
    function readCpu(text) {
        const fields = text.split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
        if (fields.length < 5) return
        const idle = fields[3] + fields[4]
        const total = fields.reduce((sum, value) => sum + value, 0)
        if (lastTotal > 0 && total > lastTotal) cpu = 1 - (idle - lastIdle) / (total - lastTotal)
        lastIdle = idle
        lastTotal = total
    }

    // One CSV line: utilisation %, memory used MiB, memory total MiB, temperature, name.
    function readGpu(text) {
        const fields = text.trim().split("\n")[0].split(",").map(field => field.trim())
        if (fields.length < 5 || isNaN(Number(fields[0]))) return
        gpu = {
            usage: Number(fields[0]) / 100,
            memoryUsedMiB: Number(fields[1]),
            memoryTotalMiB: Number(fields[2]),
            temperature: Number(fields[3]),
            name: fields.slice(4).join(", ")
        }
    }

    function refresh() {
        memoryFile.reload()
        cpuFile.reload()
        if (watchGpu && !gpuProcess.running) gpuProcess.running = true
    }

    onWatchGpuChanged: if (watchGpu) refresh()

    FileView {
        id: memoryFile
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.readMemory(text())
    }

    FileView {
        id: cpuFile
        path: "/proc/stat"
        printErrors: false
        onLoaded: root.readCpu(text())
    }

    Process {
        id: gpuProcess
        // env exits 127 when nvidia-smi is not installed, and gpu stays null.
        command: ["env", "nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,name", "--format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: root.readGpu(text)
        }
    }

    Timer {
        interval: root.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
