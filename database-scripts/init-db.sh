#!/bin/bash
set -e

# Read DB_NAME and DB_PW from .env file if it exists, otherwise use fallback
ENV_FILE="/app/.env"
DB_NAME="lernbegleitung"
DB_PASSWORD="changeMe"

if [ -f "$ENV_FILE" ]; then
    DB_NAME=$(grep -E "^DB_NAME=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '\r\n' | xargs)
    DB_PASSWORD=$(grep -E "^DB_PW=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '\r\n' | xargs)

    echo "Read from .env - DB_NAME: '$DB_NAME', DB_PASSWORD: '$DB_PASSWORD'"

    # Use fallback if DB_NAME is empty
    if [ -z "$DB_NAME" ]; then
        DB_NAME="lernbegleitung"
    fi

    # Use fallback if DB_PASSWORD is empty
    if [ -z "$DB_PASSWORD" ]; then
        DB_PASSWORD="changeMe"
    fi
fi

echo "Using DB_NAME: '$DB_NAME', DB_PASSWORD: '$DB_PASSWORD'"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create postgres role if it doesn't exist (needed for dump imports)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'postgres') THEN
            CREATE ROLE postgres WITH LOGIN SUPERUSER;
        END IF;
    END
    \$\$;

    CREATE ROLE scobees WITH LOGIN PASSWORD '$DB_PASSWORD';
    CREATE ROLE scobeesro WITH LOGIN PASSWORD '$DB_PASSWORD';

    GRANT CONNECT ON DATABASE $DB_NAME TO scobees;
    GRANT CONNECT ON DATABASE $DB_NAME TO scobeesro;

    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO scobees;
    GRANT ALL PRIVILEGES ON SCHEMA public TO scobees;

    GRANT USAGE ON SCHEMA public TO scobeesro;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO scobeesro;
EOSQL

# Import dump if .sql.gz file exists in dump directory
DUMP_DIR="/import"
if [ -d "$DUMP_DIR" ]; then
    DUMP_FILE=$(find "$DUMP_DIR" -name "*.sql.gz" -type f | head -n 1)

    if [ -n "$DUMP_FILE" ]; then
        echo "Found dump file: $DUMP_FILE"
        echo "Importing dump into database: $DB_NAME"
        gunzip -c "$DUMP_FILE" | psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$DB_NAME"
        echo "Dump import completed successfully"
    else
        echo "No .sql.gz dump file found in $DUMP_DIR"
    fi
else
    echo "Dump directory $DUMP_DIR does not exist"
fi
