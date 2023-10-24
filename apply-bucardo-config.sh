#!/bin/bash

is_running=false

bucardo_db_host=$BUCARDO_DB_HOST
bucardo_db_user=$BUCARDO_DB_USER

export PGPASSWORD=$BUCARDO_DB_PASSWORD

ls -l $bucardo_db_host

# Function to validate database connections
# This function reads each database configuration from the 'bucardo.json' file,
# attempts to connect to the database 10 times, and if all attempts fail, it will exit the script with error.
validate_db_connections() {
  # Define the JSON file path
  local json_file="/media/bucardo.json"

  # Check if the JSON file exists
  if [ -f "$json_file" ]; then
      # Loop over each database configuration in the JSON file
      jq -c '.databases[]' "${json_file}" | while read -r db; do
          # Extract database connection details from the JSON
          local id=$(echo "${db}" | jq -r '.id')
          local host=$(echo "${db}" | jq -r '.host')
          local port=$(echo "${db}" | jq -r '.port')

          # Set default values if any values are null
          [ "${host}" == "null" ] && host="localhost"
          [ "${port}" == "null" ] && port="5432"

          # Try to connect to the host:port 10 times
          for attempt in {1..10}; do
              echo "[apply-bucardo-config.sh] Attempting connect to ${dbname}@${host}:${port}"
              nc -zv "${host}" "${port}" >/dev/null 2>&1 && break || sleep 1
          done

          # If all connection attempts failed, print an error message and exit the script
          if [ $attempt -eq 10 ]; then
              echo "[apply-bucardo-config.sh] Error: Could not connect to ${dbname}@${host}:${port} as user ${user} after 10 attempts. Please review the configuration for database \"${id}\" in bucardo.json."
              exit 1
          fi
      done
  else
    # If the JSON file does not exist, print an error message and exit the script
    echo "[apply-bucardo-config.sh] Error: The 'bucardo.json' file is mandatory. Please mount it under the path: '/media/bucardo.json'. You can do this using a command like: 'docker run -v \"path_to_your_local_bucardo.json:/media/bucardo.json\" name_of_your_container'."
    exit 1
  fi
}

# Function to initialize database
init_db_against_bucardo_json() {
    # Convert the comma-separated hostnames and other host information into an array
    IFS=',' read -r -a temp <<< "$(hostname),$(hostname -i),$(getent hosts host.docker.internal | awk '{print $2}'),$(getent hosts host.docker.internal | awk '{print $1}'),${OPTIONAL_HOSTNAMES}"

    # Initialize JSON file
    json_file="/media/bucardo.json"

    # Create users and databases
    if [[ -f "$json_file" ]]; then
        jq -c '.databases[]' "${json_file}" | while read -r db; do
            id=$(echo "${db}" | jq -r '.id')
            dbname=$(echo "${db}" | jq -r '.dbname')
            host=$(echo "${db}" | jq -r '.host')
            user=$(echo "${db}" | jq -r '.user')
            pass=$(echo "${db}" | jq -r '.pass')

            # Check if $host is in the list of available hostnames
            if [[ " ${temp[*]} " == *" $host "* ]]; then
                if [[ "$(psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME - -tAc "SELECT 1 FROM pg_roles WHERE rolname='${user}'")" != "1" ]]; then

                    echo "psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "CREATE USER ${user} WITH PASSWORD '${pass}';""
                    psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "CREATE USER ${user} WITH PASSWORD '${pass}';"
                    psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "SELECT 1 FROM pg_roles WHERE rolname='${user}'"
                fi

                if [[ "$(psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -tAc "SELECT 1 FROM pg_database WHERE datname='${dbname}'")" != "1" ]]; then
                    echo psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "CREATE DATABASE ${dbname} OWNER ${user};"
                    psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "CREATE DATABASE ${dbname} OWNER ${user};"
                    psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "GRANT ALL PRIVILEGES ON DATABASE ${dbname} TO ${user};"
                    psql -h $bucardo_db_host -U $bucardo_db_user --dbname $BUCARDO_DB_NAME -c "SELECT 1 FROM pg_database WHERE datname='${dbname}'"
                fi
            fi
        done
    fi
}

# Remove all Bucardo object what can be added by this script
removeAllBucardoObjects() {
  echo "[apply-bucardo-config.sh] Remove all bucardo objects"

  echo "[apply-bucardo-config.sh] bucardo list sync $sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME"
  # Stop and remove all syncs
  for sync in $(bucardo list sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME | awk '{print $1}'); do
      echo "[apply-bucardo-config.sh] bucardo stop sync $sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME"
      bucardo stop sync $sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
      bucardo remove sync $sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
  done

  echo "[apply-bucardo-config.sh] bucardo list relgroup $sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME"
  # Remove all relation groups
  for relgroup in $(bucardo list relgroup --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME | awk '{print $1}'); do
      bucardo remove relgroup $relgroup --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
  done

echo "[apply-bucardo-config.sh] bucardo list db $sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME"
  # Remove all databases
  for db in $(bucardo list db --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME | awk '{print $1}'); do
      bucardo remove db $db --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
  done
}

# The JSON reading section
json_reading_section() {
  json_file="/media/bucardo.json"
  if [ -f "$json_file" ]; then

      # Remove all bucardo objects what might be added in previous script invocation apply-bucardo-config.sh
      removeAllBucardoObjects;

      # Read databases from the JSON file and add each to Bucardo
      jq -c '.databases[]' "${json_file}" | while read -r db; do
          id=$(echo "${db}" | jq -r '.id')
          dbname=$(echo "${db}" | jq -r '.dbname')
          host=$(echo "${db}" | jq -r '.host')
          user=$(echo "${db}" | jq -r '.user')
          pass=$(echo "${db}" | jq -r '.pass')
          port=$(echo "${db}" | jq -r '.port')

          # Assign default values if variables are null
          [ "${host}" == "null" ] && host="localhost"
          [ "${user}" == "null" ] && user="postgres"
          [ "${pass}" == "null" ] && pass="postgres"
          [ "${dbname}" == "null" ] && dbname="postgres"
          [ "${port}" == "null" ] && port=""

          # Check if we can connect to host:port
        #   for attempt in {1..10}; do
            #   nc -zv "${host}" "${port}" >/dev/null 2>&1 && break || sleep 1
        #   done

        #   if [ $attempt -lt 10 ]; then
              args=( "dbname=${dbname}" "host=${host}" "user=${user}" "pass=${pass}" "port=${port}" )
              echo "[apply-bucardo-config.sh] bucardo add db \"${id}\" \"${args[@]}\""
              bucardo add db "${id}" "${args[@]}" --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
        #   else
            #   echo "[apply-bucardo-config.sh] Warning: Cannot connect to ${host}:${port} after 10 attempts. Skipping database ${id}."
        #   fi
      done

      # Initialize index
      i=1

      # Read syncs from the JSON file and add each to Bucardo
      jq -c '.syncs[]' "${json_file}" | while read -r sync; do
          sources=$(echo "${sync}" | jq -r '.sources[]')
          targets=$(echo "${sync}" | jq -r '.targets[]')
          tables=$(echo "${sync}" | jq -r '.tables')

          # Create array of servers (sources and targets), remove duplicates
          servers=$(echo "${sources},${targets}" | tr ',' '\n' | sort -u)
          for server in $servers; do
              # Check if database was added before trying to add tables or sync
              if bucardo list db "${server}" | grep -q "Status: active"; then
                  echo "[apply-bucardo-config.sh] bucardo add table public.% relgroup=relGroup$i$server db=$server"
                  bucardo add table public.% relgroup=relGroup$i$server db=$server --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

                  echo "[apply-bucardo-config.sh] bucardo add sequence public.% relgroup=relGroup$i$server db=$server"
                  bucardo add sequence public.% relgroup=relGroup$i$server db=$server --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

                  echo "[apply-bucardo-config.sh] remove table public.spatial_ref_sys --herd=relGroup$i$server db=$server"
                  bucardo remove table public.spatial_ref_sys --herd=relGroup$i$server db=$server --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

                  echo "[apply-bucardo-config.sh] remove table public.geography_columns --herd=relGroup$i$server db=$server"
                  bucardo remove table public.geography_columns --herd=relGroup$i$server db=$server --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

                  echo "[apply-bucardo-config.sh] remove table public.geometry_columns --herd=relGroup$i$server db=$server"
                  bucardo remove table public.geometry_columns --herd=relGroup$i$server db=$server --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

                  echo "[apply-bucardo-config.sh] remove table public.geometry_columns --herd=relGroup$i$server db=$server"
                  bucardo remove table public.request_logs --herd=relGroup$i$server db=$server --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
              else
                  echo "[apply-bucardo-config.sh] Warning: Database ${server} was not added. Skipping adding tables and sync."
              fi
          done

          # Add sync for each source
          for source in $sources; do
              # Check if database was added before trying to add sync
              if bucardo list db "${source}" | grep -q "Status: active"; then
                  echo "[apply-bucardo-config.sh] bucardo add sync sync$i$source relgroup=relGroup$i$source dbs=\"$source,$targets\""
                  bucardo add sync sync$i$source relgroup=relGroup$i$source dbs="$source,$targets" onetimecopy=2 --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
              else
                  echo "[apply-bucardo-config.sh] Warning: Database ${source} was not added. Skipping adding sync."
              fi
          done

          # Increment index
          ((i++))
      done

      # List all syncs
      echo "[apply-bucardo-config.sh] Bucardo syncs:"
      bucardo list sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

      # Restart all syncs
      echo "[apply-bucardo-config.sh] Restarting all Bucardo syncs:"
      bucardo restart sync --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

      # Show Bucardo status
      echo "[apply-bucardo-config.sh] Bucardo status:"
      bucardo status --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME

      is_running=true

  fi
}

function listen_bucardo_json() {
    if $is_running ; then
      echo "[apply-bucardo-config.sh] Bucardo status:"
      bucardo status sync1source --dbhost $BUCARDO_DB_HOST --dbuser $BUCARDO_DB_USER --dbpass $BUCARDO_DB_PASSWORD --dbname $BUCARDO_DB_NAME
    else

    # File to store the last modification time
    last_modification_file="/tmp/last_modification_time"

    # Check if the json file exists
    json_file="/media/bucardo.json"
    if [ ! -f "$json_file" ]; then
        echo "[apply-bucardo-config.sh] JSON file does not exist: $json_file"
        exit 0
    fi

    # Get the current modification time
    current_modification_time=$(stat -c %Y "$json_file")

    # Get the last modification time
    if [ -f /tmp/last_modification_time ]; then
        last_modification_time=$(cat $last_modification_file)
    else
        last_modification_time=
    fi

    # Stop execution of the script if bucardo.json contains invalid configuration against db connections
    #   validate_db_connections

    # If the modification time has changed, run the JSON reading section
    if [ "$last_modification_time" != "$current_modification_time" ]; then
        echo $current_modification_time > $last_modification_file
        init_db_against_bucardo_json
        json_reading_section
    fi
  fi
}

echo "[apply-bucardo-config.sh] Starting"

while true; do sleep 10;listen_bucardo_json;   done