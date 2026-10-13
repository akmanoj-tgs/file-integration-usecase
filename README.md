# Inventory File Integration Service

A resource-conscious MuleSoft application that synchronizes full inventory extracts from Oracle WMS into store-specific inventory files for downstream e-commerce and fulfilment channels.

> **Primary engineering constraint:** process CSV files up to **500 MB** on a **0.2 vCore** runtime while preserving data quality, recoverability, idempotency, and operational visibility.

## 1. Purpose

The service receives a daily full inventory extract from Oracle WMS, validates every inventory record, separates invalid records without stopping the complete run, creates one inventory CSV per `StoreId`, and publishes the outputs to a target SFTP location.

The application supports inventory-dependent capabilities such as:

- Buy Online, Pick Up in Store (BOPIS)
- Reserve Online, Pick Up in Store (ROPIS)
- Ship from Store
- Store-level inventory availability for e-commerce

## 2. Business Flow

1. Oracle WMS creates a full inventory CSV.
2. The file is placed in the source SFTP `/inbound` directory.
3. The application starts from either:
   - a scheduled trigger, expected daily at 4:00 AM, or
   - a manual HTTP trigger for controlled reprocessing and support operations.
4. The application verifies that the expected source file exists.
5. A distributed active-run lock prevents concurrent processing.
6. An idempotency check prevents the same file from being processed twice.
7. The source is moved from `/inbound` to `/processing` before it is read.
8. Batch processing reads and processes the CSV using a streaming, low-memory approach.
9. Each record is validated and routed to either the valid or rejected path.
10. Valid records are written to store-specific staging files.
11. Rejected records are written with validation reasons for support review.
12. Staged files are published to the target SFTP using a temporary-name and rename pattern.
13. The source file is archived, the processing result is stored, the run lock is released, and a notification is sent.

![Inventory File Integration Architecture](docs/inventory-file-integration-architecture.png)

## 3. Input and Output Contract

### Input

| Item | Definition |
|---|---|
| Source | Source SFTP folder, with local folders available for development |
| Format | CSV |
| Maximum training volume | 500 MB |
| Example fields | `SKU`, `StoreId`, `Type`, `Quantity`, `Timestamp` |
| Supported inventory types | `Standard`, `Backorder` |

Example:

```csv
SKU,StoreId,Type,Quantity,Timestamp
112820SOPAAE01,WHBKS,Backorder,18,12/13/2023 20:39:00
557120HWRGSE02,WHBKS,Standard,1,12/13/2023 20:39:00
```

### Output

One CSV is produced for every unique store:

```text
inventory_<storeId>_<DD-MM-YYYY>.csv
```

Rejected records are written separately with the original business data and a clear validation reason.

## 4. Core Design Principles

### Streaming and bounded memory

The design avoids loading the complete 500 MB file into memory. CSV records are processed through Batch and record-level transformations. Large arrays, unnecessary payload copies, and full-payload logging are avoided.

### Safe file lifecycle

The source file moves through explicit lifecycle directories:

```text
/inbound → /processing → /archive
                       ↘ /error
```

Moving the file to `/processing` establishes ownership before processing. A claimed source is moved to `/error` if a technical failure occurs after the claim.

### Concurrency control

An Object Store key named `inventory::active-run` acts as a distributed active-run lock. The service handles:

- first-attempt lock acquisition,
- an already-active run,
- stale-lock detection and recovery,
- lock recovery race conditions, and
- lock already removed conditions.

### Idempotency

A processed-file key prevents accidental reprocessing:

```text
inventory::processed::<fileName>
```

Duplicate files are not claimed or processed. Any active-run lock acquired for the duplicate check is released.

### Business rejection versus technical failure

A business-invalid record does not fail the complete job. The application captures the record and validation reason, while valid records continue.

Technical failures such as SFTP connectivity, file read/write failures, transformation failures, and unexpected runtime errors follow the error-handling path and preserve enough state for recovery.

## 5. Major Flows and Responsibilities

### Entry and orchestration

- `inventory-scheduled-trigger-flow` starts the daily run.
- `inventory-manual-trigger-flow` supports controlled manual execution.
- `inventory-processing-flow` coordinates source checks, locking, idempotency, claim, and Batch processing.

### Source lifecycle

- `check-source-file-availability-subflow`
- `claim-source-file-subflow`
- `move-source-to-error-subflow`
- `finalize-successful-inventory-run-subflow`

### Lock and idempotency

- `acquire-inventory-run-lock-subflow`
- `check-file-idempotency-subflow`

### Output generation and publication

- `write-valid-store-chunk-subflow`
- rejected-record staging logic
- `publish-output-files-subflow`

### Notification and error handling

- `send-inventory-notification-flow`
- `Global_Error_Handler`

## 6. Record Validation

Each record is validated independently.

Mandatory validation rules include:

- required fields are present,
- `Quantity` is a whole number,
- `Type` is either `Standard` or `Backorder`, and
- date/time content is parseable according to the agreed input format.

The reconciliation rule for every completed run is:

```text
inputRecordCount = validRecordCount + rejectedRecordCount
```

No record should be silently lost.

## 7. Output Publication Strategy

Store-level output is first written to local staging:

```text
/staging/valid
/staging/rejected
```

Each staged file is published using the following sequence:

1. Read the local staged file.
2. Upload to the target SFTP using a temporary name.
3. Rename the remote temporary file to the final name.
4. Delete the local staged file only after successful publication.

This reduces the chance of downstream systems reading partially written files. A failed upload or rename retains the local staged file for recovery.

## 8. Status Model

Representative run statuses include:

| Status | Meaning |
|---|---|
| `PROCESSING` | The run owns the lock and processing is active |
| `MISSING_SOURCE_FILE` | The expected source file is unavailable |
| `ALREADY_RUNNING` | A fresh active-run lock exists |
| `DUPLICATE_FILE` | The source file was already processed |
| `ARCHIVE_FAILED` | Processing completed but source archive failed |
| `FAILED` | A technical failure prevented successful completion |
| `COMPLETED` | Outputs were published and finalization completed |

## 9. Configuration and Security

Non-sensitive application settings are stored in environment-specific YAML configuration files. Sensitive credentials are stored using Mule Secure Configuration Properties.

Important configuration categories:

- SFTP host, username, directories, and timeouts
- scheduler expression and timezone
- HTTP listener port
- email sender and recipients
- local staging paths
- stale-lock threshold
- feature flags such as notification enablement

The secure-properties decryption key must be supplied externally:

```text
-Dsecret.key=<value>
```

Do not commit production passwords, Connected App secrets, encryption keys, or personal credentials to Git.

## 10. Local Setup

### Prerequisites

- Anypoint Studio compatible with Mule Runtime 4.12.x
- Java version supported by the selected Mule Runtime
- Maven or Maven embedded in Anypoint Studio
- Access to a development SFTP server, or local substitutes where supported
- A test SMTP endpoint or mocked email operations for MUnit

### Test resources

Use test-specific resources under:

```text
src/test/resources/
```

Typical files:

```text
config-test.yaml
secure-local.yaml
log4j2-test.xml
```

For Studio MUnit execution, add the VM argument:

```text
-Dsecret.key=test-secret-key
```

For Maven:

```bash
mvn clean test -Dsecret.key=test-secret-key
```

## 11. Testing Strategy

MUnit suites are organized by production responsibility:

- `inventory-manual-trigger-flow-test-suite.xml`
- `inventory-processing-flow-test-suite.xml`
- `inventory-lock-subflows-test-suite.xml`
- `source-file-lifecycle-subflows-test-suite.xml`
- `publish-output-files-subflow-test-suite.xml`
- `inventory-notification-flow-test-suite.xml`

Key scenarios:

- source file available and missing,
- manual and scheduled behavior,
- active lock versus stale lock,
- duplicate and non-duplicate input,
- successful source claim,
- source move-to-error success and failure,
- valid and rejected records,
- empty staging directories,
- output publication failure,
- archive failure,
- missing lock during finalization, and
- success and failure notifications.

MUnit mocks must reproduce connector target-variable behavior. For example, when the production connector uses `target="availableSourceFiles"`, the mock must populate `vars.availableSourceFiles`, not only return a payload.

## 12. Performance and Operational Metrics

Capture the following for the 500 MB performance run:

| Metric | Measurement |
|---|---|
| Input size | Source file bytes and MB |
| Input record count | Parsed or reconciled CSV record count |
| Valid record count | Records written to store outputs |
| Rejected record count | Records written with validation reasons |
| Execution duration | Start of orchestration through finalization |
| Peak heap | Highest JVM used-heap value during the run |
| CPU | Average and peak JVM process CPU |
| Local disk usage | Staging and Mule temporary-directory growth |

Recommended tools:

- Java Flight Recorder and JDK Mission Control for heap, allocations, CPU, GC, and I/O
- JConsole for live JVM heap and threads
- PowerShell or Windows Performance Monitor for process CPU and directory size
- structured application logs for counts, duration, status, and run correlation

## 13. Logging and Observability

Logs are structured and contextual. Important fields include:

```text
runId
correlationId
triggerType
sourceFilePath
sourceFileName
runStatus
inputRecordCount
validRecordCount
rejectedRecordCount
executionDurationMs
errorType
errorDescription
```

The complete large payload is never logged.

## 14. CI/CD and Deployment

Recommended pipeline:

```text
GitHub push / pull request
→ Maven build
→ MUnit tests and coverage gates
→ package Mule application
→ authenticate to Anypoint Platform using Connected App credentials
→ deploy to the target CloudHub environment
→ smoke test
→ publish test and deployment evidence
```

Store these values in GitHub encrypted secrets:

```text
ANYPOINT_CLIENT_ID
ANYPOINT_CLIENT_SECRET
ANYPOINT_ORG_ID
ANYPOINT_ENVIRONMENT
MULE_SECURE_KEY
```

Use separate Connected Apps, environments, and encryption keys for development, QA, and production.

## 15. Recovery and Support Runbook

### Missing source

- Confirm the expected filename and source directory.
- Verify the upstream Oracle WMS delivery.
- Rerun manually after the source is available.

### Active lock remains

- Check the active-run record and its `startedAt` timestamp.
- Confirm no healthy run is still processing.
- Use stale-lock recovery rather than deleting a valid lock indiscriminately.

### File remains in processing

- Review the run logs using `runId`.
- Check `/error` and local staging directories.
- Resolve the connector or data problem before reprocessing.

### Staged output remains locally

- Determine whether the remote temporary or final file exists.
- Do not delete local staging until successful remote publication is proven.

### Archive failed after publication

- Treat outputs as potentially published.
- Repair the archive operation without republishing duplicate outputs.
- Use idempotency and run metadata to determine the safe recovery action.

## 16. Definition of Done

The application is deployment-ready when:

- all MUnit suites pass,
- critical flows meet the agreed coverage threshold,
- input count reconciles to valid plus rejected counts,
- duplicate and concurrent runs are prevented,
- output publication is atomic from a downstream perspective,
- source and lock cleanup work on success and failure,
- the 500 MB test completes within the agreed SLA,
- peak heap remains within the runtime memory budget,
- credentials and keys are externalized, and
- CI/CD deployment and post-deployment smoke tests are repeatable.

## 17. Project Structure

```text
src/
├── main/
│   ├── mule/
│   │   ├── global-config.xml
│   │   ├── inventory-scheduler-flow.xml
│   │   ├── inventory-manual-trigger-flow.xml
│   │   ├── inventory-processing-flow.xml
│   │   ├── source-file-lifecycle-subflows.xml
│   │   ├── publish-output-files-subflow.xml
│   │   ├── write-valid-store-chunk-subflow.xml
│   │   └── inventory-notification-flow.xml
│   └── resources/
│       ├── config.yaml
│       ├── secure-local.yaml
│       ├── email-templates/
│       └── weave/
└── test/
    ├── munit/
    └── resources/
        ├── config-test.yaml
        ├── secure-local.yaml
        └── log4j2-test.xml
```

---

**Application:** Inventory File Integration Service  
**Platform:** MuleSoft / Mule Runtime 4.x  
**Primary pattern:** Large-file streaming, Batch processing, store-level file segregation, resilient SFTP publication
