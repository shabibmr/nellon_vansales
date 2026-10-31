<?php
// Test-site shim: forwards GET api.php/<path>?<query> to the test report server's /api/<path>.
// Lets a static copy of web/ run under plain Apache with no proxy config. Read-only: anything but GET
// is refused, so "Refresh from Zoho" and other POSTs can't run from the test site.
const UPSTREAM = 'http://127.0.0.1:8766/api';

function fail(int $status, string $error): void {
    http_response_code($status);
    header('Content-Type: application/json');
    echo json_encode(['error' => $error]);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    fail(405, 'The test site is read-only.');
}
$path = $_SERVER['PATH_INFO'] ?? '';
if (!preg_match('#^/[A-Za-z0-9._/-]+$#', $path) || strpos($path, '..') !== false) {  // PHP 7.4 on this server
    fail(404, 'not found');
}

$headers = [];
foreach (getallheaders() as $name => $value) {
    if (strcasecmp($name, 'Authorization') === 0) {
        $headers[] = 'Authorization: ' . $value;
    }
}
$query = $_SERVER['QUERY_STRING'] ?? '';
$respHeaders = [];
$ch = curl_init(UPSTREAM . $path . ($query === '' ? '' : '?' . $query));
curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
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
]);
$body = curl_exec($ch);
if ($body === false) {
    fail(502, 'Test report server is not running (koyson-mis-test).');
}
http_response_code(curl_getinfo($ch, CURLINFO_RESPONSE_CODE));
foreach (['content-type', 'content-disposition', 'cache-control'] as $name) {
    if (isset($respHeaders[$name])) {
        header(ucwords($name, '-') . ': ' . $respHeaders[$name]);
    }
}
echo $body;
