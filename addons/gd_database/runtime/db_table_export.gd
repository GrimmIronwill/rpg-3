@tool
class_name DBTableExport
extends Resource

@export var table_name: String = ""
@export var schema_name: String = ""
@export var schema: DBSchema = null
@export var entries: Array[DBEntry] = []

static func from_table(table: DBTable) -> DBTableExport:
	var out := DBTableExport.new()
	if table == null:
		return out

	out.table_name = table.table_name
	out.schema = table.schema.duplicate(true) as DBSchema if table.schema else null
	out.schema_name = table.schema.schema_name if table.schema else ""

	for e: DBEntry in table.entries:
		out.entries.append(e.duplicate(true) as DBEntry)

	return out
