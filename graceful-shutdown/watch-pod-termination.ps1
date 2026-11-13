
# Capture Kubernetes Pod status changes during graceful termination.

$logFile = Join-Path $PSScriptRoot "pod-termination-evidence.txt"

"Monitoring started: $(Get-Date -Format o)" |
    Set-Content -Path $logFile

kubectl get pods -n gamehub --watch `
    -o custom-columns="POD:.metadata.name,PHASE:.status.phase,DELETING:.metadata.deletionTimestamp,CONTAINERS:.status.containerStatuses[*].name,EXIT-CODE:.status.containerStatuses[*].state.terminated.exitCode,LAST-EXIT:.status.containerStatuses[*].lastState.terminated.exitCode,INIT-CONTAINERS:.status.initContainerStatuses[*].name,INIT-EXIT:.status.initContainerStatuses[*].state.terminated.exitCode" |
    ForEach-Object {
        $line = "$(Get-Date -Format o) $_"
        $line
        $line | Add-Content -Path $logFile
    }
