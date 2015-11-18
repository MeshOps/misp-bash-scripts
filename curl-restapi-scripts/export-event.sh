#!/bin/bash

# export event and save to file
# Available options in URI are as follows
# http://[YOUR MISP URI]/events/xml/download/[eventid]/[withattachments]/[tags]/[from]/[to]/[last]

curl -v --request GET "http://[YOUR MISP URI]/events/[tags]]" \
-H "Accept: application/json" \
-H "Authorization: [PUT API KEY HERE remove [] symbols]" \
-o /events/eventexport.json