#!/bin/bash

# import event from export file 
# Available options in URI are as follows
# http://[YOUR MISP URI]/events/xml/download/[eventid]/[withattachments]/[tags]/[from]/[to]/[last]

curl -v --request POST "http://[YOUR MISP URI]/events" \
-H "Accept: application/xml" \
-H "Authorization: PUT API KEY HERE remove [] symbols]" \
-H "Content-Type: application/json" \
--data @events/eventexport.json