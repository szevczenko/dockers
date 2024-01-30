#!/bin/sh
echo url="https://www.duckdns.org/update?domains=hqcontroller&token=fd6161a7-e31c-4e4a-8398-c82dcc4bd156&ip=" | curl -k -o ~/projects/docker/duck.log -K -
