-- The JSON Schema validator used for settings (and later compensation configs).
begin;
\ir _helpers.psql
select plan(14);

select ok(inf.json_matches_schema('5', '{"type":"integer","minimum":1}'), 'integer within bounds');
select ok(not inf.json_matches_schema('5.5', '{"type":"integer"}'), 'non-integer refused');
select ok(not inf.json_matches_schema('"5"', '{"type":"number"}'), 'string is not a number');
select ok(inf.json_matches_schema('null', '{"anyOf":[{"type":"integer"},{"type":"null"}]}'), 'nullable via anyOf');
select ok(not inf.json_matches_schema('{"a":1,"b":2}', '{"type":"object","properties":{"a":{"type":"integer"}},"additionalProperties":false}'), 'unknown property refused');
select ok(not inf.json_matches_schema('{}', '{"type":"object","required":["a"]}'), 'missing required property refused');
select ok(inf.json_matches_schema('["a","b"]', '{"type":"array","items":{"enum":["a","b","c"]},"uniqueItems":true}'), 'enum items');
select ok(not inf.json_matches_schema('["a","a"]', '{"type":"array","uniqueItems":true}'), 'duplicate items refused');
select ok(not inf.json_matches_schema('"25:00"', '{"type":"string","pattern":"^([01]\\d|2[0-3]):[0-5]\\d$"}'), 'pattern enforced');
select ok(inf.json_matches_schema('"bankers"', '{"const":"bankers"}'), 'const');
select ok(not inf.json_matches_schema('3', '{"oneOf":[{"type":"integer"},{"minimum":0}]}'), 'oneOf requires exactly one match');
select ok(not inf.json_matches_schema('1', '{"$ref":"#/x"}'), '$ref is refused rather than skipped');
select ok(not inf.json_matches_schema('"x"', '{"type":"string","pattern":"("}'), 'an invalid pattern fails closed');
select ok(inf.json_matches_schema('{"nested":{"n":[1,2]}}', '{"type":"object","properties":{"nested":{"type":"object","properties":{"n":{"type":"array","items":{"type":"integer"},"maxItems":2}}}}}'), 'nested shapes');

select * from finish();
rollback;
