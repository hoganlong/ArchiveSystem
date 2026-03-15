# Getting Started

This guide covers prerequisites and initial setup for the Archive System.

---

## Prerequisites

### .NET 10 SDK
Download from [https://dotnet.microsoft.com/download](https://dotnet.microsoft.com/download).

Verify installation:
```bash
dotnet --version
# should output 10.x.x
```

### AWS CLI (for full pipeline only)
Required if you are using AWS RDS for PostgreSQL or S3 for images.

- Install: [https://aws.amazon.com/cli/](https://aws.amazon.com/cli/)
- Configure: `aws configure` (enter your access key, secret, and region)
- The system retrieves PostgreSQL credentials from AWS Secrets Manager at runtime — no passwords are stored in config files

If you are running PostgreSQL locally or on another provider, you can skip AWS CLI setup and configure the connection string directly in `appsettings.json`. See [configuration-reference.md](configuration-reference.md).

### Airtable Personal Access Token (PAT)
1. Go to [https://airtable.com/create/tokens](https://airtable.com/create/tokens)
2. Create a token with `data.records:read` and `schema.bases:read` scopes
3. Grant access to your base
4. Copy the token — you will add it to `appsettings.json`

---

## Clone the Project Repos

Each tool is a separate repository. Clone the ones you need:

```bash
git clone https://github.com/hoganlong/AirtableSchemaReader
git clone https://github.com/hoganlong/AirtableToPostgres
git clone https://github.com/hoganlong/AirtableImageDownloader  # optional
git clone https://github.com/hoganlong/ArtWorkHTML              # optional
```

---

## Configure appsettings.json

Each project has an `appsettings.template.json`. Copy it and fill in your values:

```bash
cp appsettings.template.json appsettings.json
```

At minimum you will need:
- `AirtableApiKey` — your Personal Access Token
- `AirtableBaseId` — the ID of your Airtable base (starts with `app`)
- PostgreSQL connection details or AWS Secrets Manager ARN

See [configuration-reference.md](configuration-reference.md) for every available field.

---

## Next Steps

- **Airtable to PostgreSQL only**: [airtable-to-postgres.md](airtable-to-postgres.md)
- **Full pipeline**: [full-system-guide.md](full-system-guide.md)
- **Adapting for your own artist/base**: [adapting-for-new-artist.md](adapting-for-new-artist.md)
