%dw 2.0
output application/java

var expectedFileName =
    (
        vars.expectedSourceFileName
            default "UNKNOWN_FILE"
    ) as String

var expectedSourcePath =
    (
        vars.sourceFilePath
            default (
                (vars.inboundDirectory default "inbound")
                ++ "/"
                ++ expectedFileName
            )
    ) as String

---
"<html>"
++ "<body>"
++ "<h2>Expected Inventory Source File Is Missing</h2>"
++ "<p>The scheduled inventory execution did not start because the expected source file was not available.</p>"
++ "<p><strong>Status:</strong> MISSING_SOURCE_FILE</p>"
++ "<p><strong>Run ID:</strong> "
++ (vars.runId default "UNKNOWN_RUN")
++ "</p>"
++ "<p><strong>Trigger:</strong> "
++ (vars.triggerType default "SCHEDULER")
++ "</p>"
++ "<p><strong>Expected filename:</strong> "
++ expectedFileName
++ "</p>"
++ "<p><strong>Expected source path:</strong> "
++ expectedSourcePath
++ "</p>"
++ "<p><strong>Business date:</strong> "
++ (vars.businessDate default "UNKNOWN_DATE")
++ "</p>"
++ "<p>Please verify that the upstream source file was generated and delivered to the inbound SFTP directory.</p>"
++ "</body>"
++ "</html>"