#!/usr/bin/env bats

# Keeps the inputs table of README.md and the inputs of action.yaml aligned.

bats_require_minimum_version 1.5.0

# action_inputs: print "<name> <default>" for every input of action.yaml.
# A required input without a default prints "-".
action_inputs() {
	awk '
		/^inputs:/ { in_inputs = 1; next }
		/^[a-z]/ { in_inputs = 0 }
		in_inputs && /^  [a-z-]+:[[:space:]]*$/ {
			if (name != "") print name, (def == "" ? "-" : def)
			name = $1; sub(/:$/, "", name); def = ""
		}
		in_inputs && /^    default:/ {
			def = $0; sub(/^    default:[[:space:]]*/, "", def); gsub(/"/, "", def)
			if (def == "") def = "\"\""
		}
		END { if (name != "") print name, (def == "" ? "-" : def) }
	' action.yaml
}

# readme_default <input>: the Default cell of the README inputs table.
readme_default() {
	grep -E "^\| \`$1\` " README.md | awk -F'|' '{ print $4 }' | tr -d ' `'
}

@test "action.yaml has inputs" {
	[ "$(action_inputs | wc -l)" -ge 10 ]
}

@test "every input of action.yaml is in the README inputs table" {
	local name def
	while read -r name def; do
		grep -Eq "^\| \`${name}\` " README.md || {
			echo "input ${name} is missing from README.md" >&2
			return 1
		}
	done < <(action_inputs)
}

@test "README defaults match action.yaml" {
	local name def readme
	while read -r name def; do
		readme="$(readme_default "${name}")"
		[ "${def}" = "${readme}" ] || {
			echo "default of ${name}: action.yaml has '${def}', README.md has '${readme}'" >&2
			return 1
		}
	done < <(action_inputs | sed 's/ ""$/ ""/')
}

@test "every input of the README table exists in action.yaml" {
	local name
	while read -r name; do
		action_inputs | grep -q "^${name} " || {
			echo "README.md documents ${name}, which action.yaml does not define" >&2
			return 1
		}
	done < <(awk '/^## Inputs/ { t = 1 } /^## Outputs/ { t = 0 } t' README.md | sed -n 's/^| `\([a-z-]*\)`.*/\1/p')
}

@test "README quick start uses the checkout major version of the repository" {
	local used
	used="$(sed -n 's/.*actions\/checkout@\(v[0-9]*\).*/\1/p' .github/workflows/ci-action.yaml | sed -n 1p)"
	[ -n "${used}" ]
	grep -q "actions/checkout@${used}" README.md
	! grep -E "actions/checkout@v[0-9]+" README.md | grep -vq "actions/checkout@${used}"
}

@test "README documents fetch-depth for VCS-derived versions" {
	grep -q "fetch-depth: 0" README.md
}

@test "every outputs of action.yaml is in the README outputs table" {
	local name
	for name in wheel-path sdist-path version; do
		grep -q "^| \`${name}\`" README.md
		grep -q "^  ${name}:" action.yaml
	done
}
