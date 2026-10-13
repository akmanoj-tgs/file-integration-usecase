%dw 2.0
output application/java

var archivePath =
    (vars.archiveDirectory default "archive")
    ++ "/"
    ++ (vars.expectedSourceFileName default "UNKNOWN_FILE")

---
"<html>"
++ "<body>"
++ "<h2>Inventory Processing Completed</h2>"
++ "<p>The inventory file completed processing successfully.</p>"
++ "<p><strong>Status:</strong> COMPLETED</p>"
++ "<p><strong>Run ID:</strong> "
++ (vars.runId default "UNKNOWN_RUN")
++ "</p>"
++ "<p><strong>Trigger:</strong> "
++ (vars.triggerType default "UNKNOWN_TRIGGER")
++ "</p>"
++ "<p><strong>Source file:</strong> "
++ (vars.sourceFilePath default "UNKNOWN_SOURCE")
++ "</p>"
++ "<p><strong>Archived file:</strong> "
++ archivePath
++ "</p>"
++ "<p><strong>Business date:</strong> "
++ (vars.businessDate default "UNKNOWN_DATE")
++ "</p>"
++ "</body>"
++ "</html>"