# Configuration Reference

All `appsettings.json` fields across the Archive System projects. No actual values are shown here — see your own `appsettings.json` or `appsettings.template.json` files for setup.

---

## Shared Fields (all projects that connect to Airtable)

| Key | Description |
|---|---|
| `AirtableApiKey` | Your Airtable Personal Access Token (PAT). Create one at airtable.com/create/tokens with `data.records:read` and `schema.bases:read` scopes. |
| `AirtableBaseId` | The ID of your Airtable base. Starts with `app`. Found in the base URL or via the Airtable API. |

---

## AirtableSchemaReader

| Key | Description |
|---|---|
| `AirtableApiKey` | See shared fields |
| `AirtableBaseId` | See shared fields |
| `SchemaOutputPath` | Path where `airtable_schema.txt` will be written. Defaults to the project directory. |

---

## AirtableToPostgres

| Key | Description |
|---|---|
| `AirtableApiKey` | See shared fields |
| `AirtableBaseId` | See shared fields |
| `SchemaFilePath` | Path to `airtable_schema.txt` produced by AirtableSchemaReader |
| `SchemaOverridesPath` | Path to `schema_overrides.json`. Defaults to the project directory. |
| `UseAwsSecretsManager` | `true` to retrieve PostgreSQL credentials from AWS Secrets Manager. Set to `false` to use inline connection details. |
| `AwsSecretsArn` | ARN of the AWS Secrets Manager secret containing PostgreSQL credentials. Required if `UseAwsSecretsManager` is `true`. |
| `AwsRegion` | AWS region for Secrets Manager (e.g., `us-east-1`). Required if using AWS Secrets Manager. |
| `PostgresHost` | PostgreSQL server hostname. Used if not using AWS Secrets Manager. |
| `PostgresPort` | PostgreSQL port. Defaults to `5432`. |
| `PostgresDatabase` | Database name. |
| `PostgresUsername` | Database username. Used if not using AWS Secrets Manager. |
| `PostgresPassword` | Database password. Used if not using AWS Secrets Manager. Do not commit this to source control. |
| `SyncBatchSize` | Number of records to process per batch during sync. Defaults to 100. |

---

## AirtableImageDownloader

| Key | Description |
|---|---|
| `AirtableApiKey` | See shared fields |
| `AirtableBaseId` | See shared fields |
| `ArtworkOutputPath` | Local directory where artwork images are saved. |
| `ArchiveOutputPath` | Local directory where archive images are saved. |
| `TableFilter` | Optional list of table names to download images from. If empty, all tables with attachment fields are included. |

---

## ArtWorkHTML

| Key | Description |
|---|---|
| `UseAwsSecretsManager` | See AirtableToPostgres |
| `AwsSecretsArn` | See AirtableToPostgres |
| `AwsRegion` | See AirtableToPostgres |
| `PostgresHost` | See AirtableToPostgres |
| `PostgresPort` | See AirtableToPostgres |
| `PostgresDatabase` | See AirtableToPostgres |
| `PostgresUsername` | See AirtableToPostgres |
| `PostgresPassword` | See AirtableToPostgres |
| `OutputPath` | Directory where generated HTML files are written. |
| `SiteTitle` | Title used in generated HTML pages. |
| `S3BaseUrl` | Base URL for images served from S3. |

---

## getspecialimages

| Key | Description |
|---|---|
| `PostgreSQL:SecretArn` | ARN of the AWS Secrets Manager secret containing PostgreSQL credentials |
| `PostgreSQL:Host` | PostgreSQL server hostname |
| `PostgreSQL:Database` | Database name |
| `PostgreSQL:Port` | PostgreSQL port. Defaults to `5432` |
| `S3:BucketName` | S3 bucket containing source images |
| `S3:Prefix` | S3 key prefix for source images (e.g. `jpg/`) |
| `Output:Directory` | Local directory where renamed images are saved. Defaults to `images` |

---

## checks3vslocal

| Key | Description |
|---|---|
| `S3:LocalPath` | Local directory to compare against S3 |
| `S3:S3Uri` | S3 URI to compare against (e.g. `s3://bucket/prefix/`) |
| `S3:Region` | AWS region. Defaults to `us-east-1` |

---

## AWS Secrets Manager Setup

If `UseAwsSecretsManager` is `true`, the secret must contain a JSON object with these keys:

```json
{
  "host": "your-rds-endpoint",
  "port": "5432",
  "dbname": "your-database",
  "username": "your-username",
  "password": "your-password"
}
```

The AWS CLI must be configured with credentials that have `secretsmanager:GetSecretValue` permission on the secret ARN.

For local development without AWS, set `UseAwsSecretsManager` to `false` and provide the PostgreSQL details inline in `appsettings.json`. Do not commit the file with credentials.

---

## appsettings.template.json

Each project includes an `appsettings.template.json` with placeholder values. Copy it to `appsettings.json` and fill in your values:

```bash
cp appsettings.template.json appsettings.json
```

`appsettings.json` is listed in `.gitignore` to prevent accidental credential commits.
