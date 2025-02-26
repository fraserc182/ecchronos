#!/bin/bash
#
# Copyright 2019 Telefonaktiebolaget LM Ericsson
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

source variables.sh

echo "Installing virtualenv"

# Install virtualenv and behave
if [ -z "${CI}" ]; then
  pip install --user virtualenv
  virtualenv "$VENV_DIR"
  source "$VENV_DIR"/bin/activate
fi

echo "Installing behave"

pip install behave
pip install requests
pip install jsonschema

BASE_DIR="$TEST_DIR"/ecchronos-binary-${project.version}
CONF_DIR="$BASE_DIR"/conf
PYLIB_DIR="$BASE_DIR"/pylib

CERTIFICATE_DIRECTORY=${project.build.directory}/certificates/cert

# Change configuration for ecchronos

## Connection
# Remove comment lines
sed '/^\s*#.*/d' -i "$CONF_DIR"/ecc.yml
# Replace native/jmx host (it's important not to change the REST host)
sed "/cql:/{n;s/host: .*/host: $CASSANDRA_IP/}" -i "$CONF_DIR"/ecc.yml
sed "/jmx:/{n;s/host: .*/host: $CASSANDRA_IP/}" -i "$CONF_DIR"/ecc.yml
# Replace native/jmx ports
sed "s/port: 9042/port: $CASSANDRA_NATIVE_PORT/g" -i "$CONF_DIR"/ecc.yml
sed "s/port: 7199/port: $CASSANDRA_JMX_PORT/g" -i "$CONF_DIR"/ecc.yml

## Security
sed '/cql:/{n;/credentials/{n;s/enabled: .*/enabled: true/}}' -i "$CONF_DIR"/security.yml
sed '/cql:/{n;/credentials/{n;/enabled: .*/{n;s/username: .*/username: eccuser/}}}' -i "$CONF_DIR"/security.yml
sed '/cql:/{n;/credentials/{n;/enabled: .*/{n;/username: .*/{n;s/password: .*/password: eccpassword/}}}}' -i "$CONF_DIR"/security.yml

sed "/tls:/{n;s/enabled: .*/enabled: true/}" -i "$CONF_DIR"/security.yml
sed "s;keystore: .*;keystore: $CERTIFICATE_DIRECTORY/.keystore;g" -i "$CONF_DIR"/security.yml
sed "s/keystore_password: .*/keystore_password: ecctest/g" -i "$CONF_DIR"/security.yml
sed "s;truststore: .*;truststore: $CERTIFICATE_DIRECTORY/.truststore;g" -i "$CONF_DIR"/security.yml
sed "s/truststore_password: .*/truststore_password: ecctest/g" -i "$CONF_DIR"/security.yml

# Logback

sed 's;^\(\s*\)\(<appender-ref ref="STDOUT" />\)\s*$;\1<!-- \2 -->;g' -i "$CONF_DIR"/logback.xml


## Scheduler

sed "s/#\?scheduler.run.interval.time=[0-9]\+/scheduler.run.interval.time=1/g" -i "$CONF_DIR"/ecc.cfg
sed "s/#\?scheduler.run.interval.time.unit=seconds\+/scheduler.run.interval.time.unit=seconds/g" -i "$CONF_DIR"/ecc.cfg

## Special config for test.table1

cat <<EOF > "$CONF_DIR"/schedule.yml
keyspaces:
  - name: test
    tables:
    - name: table1
      interval:
        time: 1
        unit: days
      unwind_ratio: 0.1
      alarm:
        warn:
          time: 4
          unit: days
        error:
          time: 8
          unit: days

EOF

cd $PYLIB_DIR

python setup.py install

cd $BASE_DIR

bin/ecctool start -p $PIDFILE

CHECKS=0
MAX_CHECK=10

echo "Waiting for REST server to start..."
until $(curl --silent --fail --head --output /dev/null http://localhost:8080/repair-management/v1/status); do
    if [ "$CHECKS" -eq "$MAX_CHECK" ]; then
        if [ -f "$BASE_DIR"/ecc.debug.log ]; then
            echo "===Debug log content==="
            cat "$BASE_DIR"/ecc.debug.log
            echo "===Debug log content==="
        else
            echo "No logs found"
        fi
        exit 1
    fi

    echo "..."
    CHECKS=$(($CHECKS+1))
    sleep 2
done

echo "Starting behave"

cd "$TEST_DIR"

behave --define ecctool="$BASE_DIR"/bin/ecctool
RETURN=$?

if [ -f $PIDFILE ]; then
    cd -
    bin/ecctool stop -p $PIDFILE
fi

exit $RETURN