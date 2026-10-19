<?php
// Production shim: forwards api.php/<path> to the prod report server's /api/<path>.
// The Python server checks the Zoho web-tab JWT (Authorization: Bearer). This file only relays it.
const UPSTREAM = 'http://127.0.0.1:8767/api';

function fail(int $status, string $error): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode(['error' => $error]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if ($method !== 'GET' && $method !== 'POST') {
    fail(405, 'Method not allowed.');
}
$path = $_SERVER['PATH_INFO'] ?? '';
if (!preg_match('#^/[A-Za-z0-9._/-]+$#', $path) || strpos($path, '..') !== false) {
    fail(404, 'not found');
}

$headers = [];
foreach (getallheaders() as $name => $value) {
    if (strcasecmp($name, 'Authorization') === 0 || strcasecmp($name, 'Content-Type') === 0) {
        $headers[] = $name . ': ' . $value;
    }
}
$query = $_SERVER['QUERY_STRING'] ?? '';
$respHeaders = [];
$ch = curl_init(UPSTREAM . $path . ($query === '' ? '' : '?' . $query));
$opts = [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CUSTOMREQUEST => $method,
    CURLOPT_HTTPHEADER => $headers,
    CURLOPT_CONNECTTIMEOUT => 5,
    CURLOPT_TIMEOUT => 120,
    CURLOPT_HEADERFUNCTION => function ($ch, $line) use (&$respHeaders) {
        $parts = explode(':', $line, 2);
        if (count($parts) === 2) {
            $respHeaders[strtolower(trim($parts[0]))] = trim($parts[1]);
        }
        return strlen($line);
    },
];
if ($method === 'POST') {
    $opts[CURLOPT_POSTFIELDS] = file_get_contents('php://input');
}
curl_setopt_array($ch, $opts);
$body = curl_exec($ch);
if ($body === false) {
    fail(502, 'Report server is not running (koyson-mis-zoho).');
}
http_response_code(curl_getinfo($ch, CURLINFO_RESPONSE_CODE));
foreach (['content-type', 'content-disposition', 'cache-control'] as $name) {
    if (isset($respHeaders[$name])) {
        header(ucwords($name, '-') . ': ' . $respHeaders[$name]);
    }
}
echo $body;
