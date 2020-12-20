#!/bin/bash

DIR_KSQL_INIT_CONFIG='./ksql'
FILE_KSQL_CONFIG='./ksql_config.json'
KAFKA_BROKER_HOST='broker:9092'
KAFKA_REST_PROXY_URL='http://localhost:8082'
KAFKA_CONNECT_URL='http://localhost:8083'
KAFKA_SCHEMA_URL='http://schema-registry:8081'
KAFKA_KSQL_DB_URL='http://localhost:8088'
DB_CONNECTION_URL='jdbc:postgresql://db:5432/raw?user=sink&password=d5_TDyp52HhMceA82sv0u_30wLX2o1_j520p8x'

APP_ID=substrate_streamer
APP_MODE=dev
APP_NETWORK=polkadot
APP_PREFIX=$(echo "$APP_ID"_"$APP_MODE"_"$APP_NETWORK" | tr '[:lower:]' '[:upper:]')

# {
#  "ksql": "",
#  "streamsProperties": {}
# }

read -r -d '' KSQL_FILE_TEMPLATE <<-EOM
{
  "ksql": {KSQL},
  "streamsProperties": {}
}
EOM

if ! type "jq" >/dev/null; then
  echo "The \"jq\" command not found"
  exit 1
fi



docker-compose up -d zookeeper broker
docker-compose up -d --build schema-registry connect control-center ksqldb-server ksqldb-cli ksql-datagen rest-proxy db

echo "Starting ksql containers..."
sleep 2m # we should wait a little bit


KAFKA_API_ATTEMPT_COUNTER=0
KAFKA_API_ATTEMPTS=600

echo "Waiting for kafka broker..."

while [[ "$(curl -sX GET "$KAFKA_REST_PROXY_URL/brokers" \
  -H "Content-Type: application/vnd.kafka.v2+json" | jq -r '.brokers[0]')" = null ]]; do
    if [ ${KAFKA_API_ATTEMPTS} -eq ${KAFKA_API_ATTEMPT_COUNTER} ];then
      echo "Cannot connect to Kafka API instance. Max attempts reached"
      exit 1
    fi

    printf '.'
    KAFKA_API_ATTEMPT_COUNTER=$((KAFKA_API_ATTEMPT_COUNTER+1))
    sleep 1
done

if [ ! -s $FILE_KSQL_CONFIG ]
then
  echo "KSQL config not found \"$FILE_KSQL_CONFIG\""
  exit
fi

KSQL_CONFIG+=$(<"$FILE_KSQL_CONFIG")

if [[ $(jq -r '.topics[0]' <<<"$KSQL_CONFIG") == null ]]; then
  echo "KSQL config \"$FILE_KSQL_CONFIG\" doesn't contains \"topic\" entries"
  exit
fi

for kafka_topic in $(jq -r '.topics[].name' <<<"$KSQL_CONFIG"); do
  kafka_topic="$APP_PREFIX"_"$kafka_topic"
  if [[ $(curl -sX GET "$KAFKA_REST_PROXY_URL/topics" \
    -H "Content-Type: application/vnd.kafka.v2+json" | jq -r '. | index("'"$kafka_topic"'")') == null ]]; then
    echo "Creating topic \"$kafka_topic\""
    docker-compose exec broker kafka-topics --create --bootstrap-server "$KAFKA_BROKER_HOST" \
      --replication-factor 1 \
      --partitions 1 \
      --topic "$kafka_topic"
  else
    echo "Topic \"$kafka_topic\" already exists"
  fi

done

KSQL_ATTEMPT_COUNTER=0
KSQL_MAX_ATTEMPTS=600

echo "Waiting for KSQL server..."

while [[ "$(curl -sX GET "$KAFKA_KSQL_DB_URL/info" | jq -r '.KsqlServerInfo')" = null ]]; do
    if [ ${KSQL_ATTEMPT_COUNTER} -eq ${KSQL_MAX_ATTEMPTS} ];then
      echo "Cannot connect to KSQL instance. Max attempts reached"
      exit 1
    fi

    printf '.'
    KSQL_ATTEMPT_COUNTER=$((KSQL_ATTEMPT_COUNTER+1))
    sleep 1
done

KSQL_SERVER_VERSION=$(curl -sX GET "$KAFKA_KSQL_DB_URL/info" | jq -r '.KsqlServerInfo.version')
echo "KSQL server is ready. Version \"$KSQL_SERVER_VERSION\""


if [ ! -d $DIR_KSQL_INIT_CONFIG ]; then
  echo "KSQL migrations dir \"$DIR_KSQL_INIT_CONFIG\" not exists"
  exit 1
fi

if [ -z "$(ls -A $DIR_KSQL_INIT_CONFIG/*.sql)" ]; then
  echo "KSQL migrations dir \"$DIR_KSQL_INIT_CONFIG\" does not contains *.sql files"
  exit 1
fi

for file in "$DIR_KSQL_INIT_CONFIG"/*.sql; do
  echo "Loading KSQL migrations \"$file\""
  GEN_KSQL=$(<"$file")

  if [ -z "$GEN_KSQL" ]; then
    echo "Loaded KSQL migrations file is empty"
    echo "Please, check \"$file\""
    continue
  fi

  # TODO: Use params array
  for param in {APP_ID,APP_MODE,APP_NETWORK,APP_PREFIX}; do
    GEN_KSQL=${GEN_KSQL//\{$param\}/${!param}}
  done

  GEN_KSQL=$(echo "$GEN_KSQL" | jq -Rs)
  KSQL_INIT="${KSQL_FILE_TEMPLATE//\{KSQL\}/$GEN_KSQL}"

  KSQL_RESP_MESSAGE=$(curl -sX "POST" "$KAFKA_KSQL_DB_URL/ksql" \
    -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
    --data "$KSQL_INIT" | jq '. | if type == "array" then null else .message end')

  if [[ "$KSQL_RESP_MESSAGE" != null ]]; then
    echo "$KSQL_RESP_MESSAGE"
  fi
done

#{
#  "name": "",
#  "config": {
#    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
#    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
#    "value.converter": "io.confluent.connect.avro.AvroConverter",
#    "topics": "BLOCK",
#    "connection.url": "jdbc:postgresql://db:5432/raw?user=sink&password=d5_TDyp52HhMceA82sv0u_30wLX2o1_j520p8x",
#    "dialect.name": "PostgreSqlDatabaseDialect",
#    "insert.mode": "",
#    "table.name.format": "",
#    "pk.mode": "",
#    "pk.fields": "",
#    "auto.create": false,
#    "auto.evolve": false,
#    "value.converter.schema.registry.url": "http://schema-registry:8081"
#  }
#}

read -r -d '' KAFKA_FILE_CONNECTOR_TEMPLATE <<-EOM
{
  "name": "",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "topics": "BLOCK",
    "connection.url": "",
    "dialect.name": "PostgreSqlDatabaseDialect",
    "insert.mode": "",
    "table.name.format": "",
    "pk.mode": "",
    "pk.fields": "",
    "auto.create": false,
    "auto.evolve": false,
    "value.converter.schema.registry.url": ""
  }
}
EOM

for kafka_connector in $(jq -c '.connectors[]' <<<"$KSQL_CONFIG"); do
  for param in {APP_ID,APP_MODE,APP_NETWORK,APP_PREFIX}; do
    kafka_connector=${kafka_connector//\{$param\}/${!param}}
  done
  # Merge config with template
  KAFKA_CONNECTOR_CONFIG=$(echo "$KAFKA_FILE_CONNECTOR_TEMPLATE" "$kafka_connector" | jq -s '.[0] * .[1]')

  # Fill up variables
  KAFKA_CONNECTOR_CONFIG=$(echo "$KAFKA_CONNECTOR_CONFIG" | jq --arg DB_CONNECTION_URL "$DB_CONNECTION_URL" '.config["connection.url"] = $DB_CONNECTION_URL')
  KAFKA_CONNECTOR_CONFIG=$(echo "$KAFKA_CONNECTOR_CONFIG" | jq --arg KAFKA_SCHEMA_URL "$KAFKA_SCHEMA_URL" '.config["value.converter.schema.registry.url"] = $KAFKA_SCHEMA_URL')


  echo "Creating connector $(echo "$KAFKA_CONNECTOR_CONFIG" | jq '.name')"
  KAFKA_CONNECT_RESP_MESSAGE=$(curl -sX "POST" "$KAFKA_CONNECT_URL"/connectors \
    -H "Accept:application/json" -H "Content-Type: application/json" \
    --data "$KAFKA_CONNECTOR_CONFIG" | jq '.message')

  if [[ "$KAFKA_CONNECT_RESP_MESSAGE" != null ]]; then
    echo "$KAFKA_CONNECT_RESP_MESSAGE"
  fi
done