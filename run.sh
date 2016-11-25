#!/bin/bash

docker run -ti -p5044:5044 moikorg/logstash5.0 -f /etc/logstash/conf.d

