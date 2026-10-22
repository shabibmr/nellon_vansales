<?php
// Published cashflow snapshot. Apache denies forecast.json; this script returns it
// only after the Zoho Books web-tab JWT checks out. Same rules as reports/web_auth.py.
// Secret stays in the worktree .env.mis (MIS_JWT_SECRET). Do not put it in this file.

const FORECAST = __DIR__ . '/forecast.json';
const ENV_FILE = '/home/nellon/nellon_vansales/.claude/worktrees/mis-date-range/reports/mis/.env.mis';
const LEEWAY = 60;
const OPEN_FROM_TAB = 'Open this report from the Zoho Books web tab.';

function fail($status, $error)
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode(array('error' => $error));
    exit;
}

function env_value($name)
{
    if (!is_readable(ENV_FILE)) {
        return '';
    }
    $lines = file(ENV_FILE, FILE_IGNORE_NEW_LINES);
    if ($lines === false) {
        return '';
    }
    $prefix = $name . '=';
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#') {
            continue;
        }
        if (strpos($line, $prefix) !== 0) {
            continue;
        }
        $value = trim(substr($line, strlen($prefix)));
        $len = strlen($value);
        if ($len >= 2 && ($value[0] === '"' || $value[0] === "'") && $value[$len - 1] === $value[0]) {
            $value = substr($value, 1, -1);
        }
        return $value;
    }
    return '';
}

function b64d($part)
{
    $pad = strlen($part) % 4;
    if ($pad) {
        $part .= str_repeat('=', 4 - $pad);
    }
    $raw = base64_decode(strtr($part, '-_', '+/'), true);
    if ($raw === false) {
        throw new RuntimeException('bad b64');
    }
    return $raw;
}

function verify($token, $secret)
{
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        fail(401, OPEN_FROM_TAB);
    }
    try {
        $header = json_decode(b64d($parts[0]), true);
        $claims = json_decode(b64d($parts[1]), true);
        $sig = b64d($parts[2]);
    } catch (Throwable $e) {
        fail(401, OPEN_FROM_TAB);
    }
    if (!is_array($header) || (isset($header['alg']) ? $header['alg'] : '') !== 'HS256') {
        fail(401, OPEN_FROM_TAB);
    }
    $expected = hash_hmac('sha256', $parts[0] . '.' . $parts[1], $secret, true);
    if (!is_string($sig) || strlen($sig) !== strlen($expected) || !hash_equals($expected, $sig)) {
        fail(401, OPEN_FROM_TAB);
    }
    if (!is_array($claims)) {
        fail(401, OPEN_FROM_TAB);
    }
    $now = time();
    $exp = isset($claims['exp']) ? $claims['exp'] : null;
    if (!is_numeric($exp) || $now > $exp + LEEWAY) {
        fail(401, OPEN_FROM_TAB);
    }
    if (isset($claims['nbf']) && is_numeric($claims['nbf']) && $now + LEEWAY < $claims['nbf']) {
        fail(401, OPEN_FROM_TAB);
    }
    if ((isset($claims['token_type']) ? $claims['token_type'] : '') !== 'access') {
        fail(401, OPEN_FROM_TAB);
    }
    $wantOrg = env_value('MIS_ZOHO_ORG_ID');
    if ($wantOrg !== '' && (string) (isset($claims['organization_id']) ? $claims['organization_id'] : '') !== $wantOrg) {
        fail(401, OPEN_FROM_TAB);
    }
    $wantTab = env_value('MIS_ZOHO_TAB_ID');
    if ($wantTab !== '' && (string) (isset($claims['tab_id']) ? $claims['tab_id'] : '') !== $wantTab) {
        fail(401, OPEN_FROM_TAB);
    }
}

if ((isset($_SERVER['REQUEST_METHOD']) ? $_SERVER['REQUEST_METHOD'] : 'GET') !== 'GET') {
    fail(405, 'Method not allowed.');
}

$secret = env_value('MIS_JWT_SECRET');
if ($secret === '') {
    fail(503, 'Server auth is not configured (MIS_JWT_SECRET).');
}

$bearer = isset($_SERVER['HTTP_AUTHORIZATION']) ? $_SERVER['HTTP_AUTHORIZATION'] : '';
if ($bearer === '' && function_exists('getallheaders')) {
    foreach (getallheaders() as $name => $value) {
        if (strcasecmp($name, 'Authorization') === 0) {
            $bearer = $value;
            break;
        }
    }
}
if (!preg_match('/^Bearer\s+(\S+)\s*$/i', $bearer, $m)) {
    fail(401, OPEN_FROM_TAB);
}
verify($m[1], $secret);

if (!is_readable(FORECAST)) {
    fail(404, 'Forecast is not published.');
}
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
$size = filesize(FORECAST);
if ($size !== false) {
    header('Content-Length: ' . $size);
}
readfile(FORECAST);
