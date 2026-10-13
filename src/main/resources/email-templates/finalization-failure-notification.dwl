%dw 2.0
output application/java

var failureStatus =
    (
        vars.runStatus
            default "PUBLICATION_FAILED"
    ) as String

var failureErrorType =
    (
        vars.notificationErrorType
            default "UNKNOWN_ERROR"
    ) as String

var failureDescription =
    (
        vars.notificationErrorDescription
            default "Inventory finalization failed"
    ) as String

var processingPath =
    (
        vars.processingSourceFilePath
            default "UNKNOWN_PROCESSING_PATH"
    ) as String

var expectedArchivePath =
    (
        (vars.archiveDirectory default "archive")
        ++ "/"
        ++ (vars.expectedSourceFileName default "UNKNOWN_FILE")
    ) as String

---
"<html>"
++ "<body>"
++ "<h2>Inventory Finalization Failed</h2>"
++ "<p>The Batch Job completed, but output publication or source archival did not complete successfully.</p>"
++ "<p><strong>Status:</strong> "
++ failureStatus
++ "</p>"
++ "<p><strong>Run ID:</strong> "
++ (vars.runId default "UNKNOWN_RUN")
++ "</p>"
++ "<p><strong>Trigger:</strong> "
++ (vars.triggerType default "UNKNOWN_TRIGGER")
++ "</p>"
++ "<p><strong>Source file:</strong> "
++ (vars.sourceFilePath default "UNKNOWN_SOURCE")
++ "</p>"
++ "<p><strong>Processing path:</strong> "
++ processingPath
++ "</p>"
++ "<p><strong>Expected archive path:</strong> "
++ expectedArchivePath
++ "</p>"
++ "<p><strong>Error type:</strong> "
++ failureErrorType
++ "</p>"
++ "<p><strong>Error description:</strong> "
++ failureDescription
++ "</p>"
++ "<p><strong>Business date:</strong> "
++ (vars.businessDate default "UNKNOWN_DATE")
++ "</p>"
++ "</body>"
++ "</html>"