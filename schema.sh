#!/bin/bash

# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash

POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -u|--user)
            USER="$2"
            shift 2 # shift to next parameter
            ;;
        -d|--database)
            DATABASE="$2"
            shift 2 # shift to next parameter
            ;;
        -s|--schema)
            SCHEMA="$2"
            shift 2 # shift to next parameter
            ;;
    esac
done
set -- "$POSITIONAL[@]"

if [ -z "$USER" ]; then
    USER="postgres"
fi

if [ -z "$DATABASE" ]; then
    DATABASE="postgres"
fi

if [ -z "$SCHEMA" ]; then
    SCHEMA="public"
fi

psql -U $USER -d $DATABASE -c "

SELECT c.table_name, 
	c.column_name, 
	c.data_type, 
	c.udt_name,
	(SELECT string_agg(e.enumlabel::TEXT, ', ')
		FROM pg_type t 
		   JOIN pg_enum e on t.oid = e.enumtypid  
		   JOIN pg_catalog.pg_namespace n ON n.oid = t.typnamespace WHERE t.typname = c.udt_name) enum_values,
	c.is_nullable, 
	c.character_maximum_length,
	(SELECT tc.constraint_type FROM information_schema.key_column_usage kcu
		JOIN information_schema.table_constraints tc 
			ON tc.table_name = c.table_name AND tc.constraint_name = kcu.constraint_name
		WHERE c.column_name = kcu.column_name 
			AND c.table_name = kcu.table_name 
			AND tc.constraint_type = 'PRIMARY KEY' LIMIT 1
	) primary_key,
	(SELECT tc.constraint_type FROM information_schema.key_column_usage kcu
		JOIN information_schema.table_constraints tc 
			ON tc.table_name = c.table_name AND tc.constraint_name = kcu.constraint_name
		WHERE c.column_name = kcu.column_name 
			AND c.table_name = kcu.table_name 
			AND tc.constraint_type = 'FOREIGN KEY' LIMIT 1
	) foreign_key,
	(SELECT ccu.table_name FROM information_schema.key_column_usage kcu
		JOIN information_schema.table_constraints tc 
			ON tc.table_name = c.table_name AND tc.constraint_name = kcu.constraint_name
		JOIN information_schema.constraint_column_usage ccu
			ON tc.constraint_name = ccu.constraint_name
		WHERE c.column_name = kcu.column_name 
			AND c.table_name = kcu.table_name 
			AND tc.constraint_type = 'FOREIGN KEY' LIMIT 1
	) reference_table,
	(SELECT ccu.column_name FROM information_schema.key_column_usage kcu
		JOIN information_schema.table_constraints tc 
			ON tc.table_name = c.table_name AND tc.constraint_name = kcu.constraint_name
		JOIN information_schema.constraint_column_usage ccu
			ON tc.constraint_name = ccu.constraint_name
		WHERE c.column_name = kcu.column_name 
			AND c.table_name = kcu.table_name 
			AND tc.constraint_type = 'FOREIGN KEY' LIMIT 1
	) reference_column
	
FROM information_schema.columns c 
	JOIN information_schema.tables t on c.table_name = t.table_name
WHERE c.table_schema = '$SCHEMA' AND t.table_type = 'BASE TABLE'" | sed 's/, /<BR\/>/g' | head -n -2 | tail -n+3 | awk -F"|" '
function ltrim(s) {
    sub(/^[ \t\r\n]+/, "", s);
    return s
}

function rtrim(s) {
    sub(/[ \t\r\n]+$/, "", s);
    return s
}

function trim(s) {
    return rtrim(ltrim(s));
}

BEGIN {
    print("digraph {")
    print("graph [overlap=false;splines=true;regular=true];")
    print("node [shape=Mrecord; fontname=\"Courier New\" style=\"filled, bold\" fillcolor=\"white\", fontcolor=\"black\"];")
}

{
   if (length(currentTableName) > 0 && $1 != currentTableName) {
       print("</TABLE>>]")
   }
 
   if ($1 != currentTableName) {
        print("")
        print(trim($1) " [shape=plaintext; label=<")
        print("<TABLE BORDER=\"1\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"3\">")
        print("<TR>")
        print("<TD COLSPAN=\"5\" BGCOLOR=\"black\"><FONT color=\"white\"><B>" trim($1) "</B></FONT></TD>")
        print("</TR>")

        print("<TR>")
        print("<TD>column</TD>")
        print("<TD>type</TD>")
        print("<TD>nullable</TD>")
        print("<TD>PK</TD>")
        print("<TD>FK</TD>")
        print("</TR>")
        port = 0
    }

    print("<TR>")
    print("<TD port=\"f" ++port "\">"trim($2)"</TD>")
    print("<TD>"trim($4)"</TD>")
    print("<TD>"trim($6)"</TD>")
    print("<TD>"trim($8)"</TD>")
    print("<TD>"trim($9)"</TD>")
    print("</TR>")

    if (trim($9) == "FOREIGN KEY") {
        edges[++edgeCounter] = trim($1) " -> " trim($10) ";"
    }

    if (length(trim($5)) > 0) {
        nodes[++nodeCounter] = trim($4) "[shape=\"box\", style=\"rounded\", label=<<B>" trim($4) " (enum)</B><BR/>" trim($5) ">];"
        edges[++edgeCounter] = trim($1) ":f" port " -> " trim($4) ";"
    }
   
    currentTableName = $1
}

END {
    print("</TABLE>>]")

    for (node in nodes) {
        print(nodes[++i])
    }
    i = 0
    for (edge in edges){
        print(edges[++i])
    }
    print("}")
}'
