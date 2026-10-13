<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Cache-Control: no-cache, no-store, must-revalidate');

$runs_dir = '/home/nellon/nellon_vansales/zoho_endpoints/settle_runs';

$csv_files = glob($runs_dir . '/settle_log_*.csv');
if (!$csv_files) {
    echo json_encode([
        'rows' => [],
        'totalOk' => 0,
        'totalSkip' => 0,
        'totalFail' => 0,
        'totalApplied' => 0.0,
        'startTimeIso' => null,
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

// Sort by filename desc (ISO timestamp is embedded in filename)
rsort($csv_files);

$latest_csv = $csv_files[0];

$rows = [];
if (($handle = fopen($latest_csv, 'r')) !== false) {
    $header_line = fgets($handle);
    if ($header_line !== false) {
        $header_line = preg_replace('/^\xEF\xBB\xBF/', '', trim($header_line));
        $delimiter = (strpos($header_line, '|') !== false) ? '|' : ',';
        $header = explode($delimiter, $header_line);
        $header_count = count($header);

        while (($line = fgets($handle)) !== false) {
            $line = trim($line);
            if ($line === '') continue;
            $parts = explode($delimiter, $line);
            $count = count($parts);
            if ($count === $header_count) {
                $rows[] = array_combine($header, $parts);
            } elseif ($count > 10) {
                $padded = array_pad($parts, $header_count, '');
                $rows[] = array_combine($header, array_slice($padded, 0, $header_count));
            }
        }
    }
    fclose($handle);
}

$total_ok = 0;
$total_warn = 0;
$total_skip = 0;
$total_fail = 0;
$total_applied = 0.0;

foreach ($rows as $r) {
    $st = isset($r['status']) ? $r['status'] : '';
    if ($st === 'OK') {
        $total_ok++;
        $total_applied += (float)(isset($r['amount_applied']) ? $r['amount_applied'] : 0);
    } elseif ($st === 'WARN') {
        $total_warn++;
        $total_applied += (float)(isset($r['amount_applied']) ? $r['amount_applied'] : 0);
    } elseif ($st === 'SKIP') {
        $total_skip++;
    } elseif ($st === 'FAIL') {
        $total_fail++;
    }
}

$start_time = !empty($rows) ? (isset($rows[0]['timestamp']) ? $rows[0]['timestamp'] : null) : null;
$end_time = !empty($rows) ? (isset($rows[count($rows) - 1]['timestamp']) ? $rows[count($rows) - 1]['timestamp'] : null) : null;

$response = [
    'rows' => $rows,
    'totalOk' => $total_ok,
    'totalWarn' => $total_warn,
    'totalSkip' => $total_skip,
    'totalFail' => $total_fail,
    'totalApplied' => round($total_applied, 2),
    'startTimeIso' => $start_time,
    'endTimeIso' => $end_time,
    'logFile' => basename($latest_csv),
];

echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
