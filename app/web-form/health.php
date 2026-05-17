<?php
// =============================================================================
// Health Check Endpoint - /health.php
// =============================================================================
// Devuelve JSON con el estado de la app y la conexión a la BD.
// Usado por el workflow health-check-aws.yml de GitHub Actions.
//
// Respuestas:
//   HTTP 200 + {"status":"ok"}       → App y BD funcionando
//   HTTP 503 + {"status":"error"}    → Fallo en la conexión a BD
// =============================================================================

header('Content-Type: application/json');

$db_host     = getenv("DB_HOST");
$db_user     = getenv("DB_USER");
$db_password = getenv("DB_PASSWORD");
$db_name     = getenv("DB_NAME");
$db_port     = getenv("DB_PORT") ?: 3306;

$response = [
    "status"    => "ok",
    "timestamp" => date("Y-m-d H:i:s"),
    "database"  => "unknown"
];

try {
    $conn = new mysqli($db_host, $db_user, $db_password, $db_name, $db_port);

    if ($conn->connect_error) {
        throw new Exception("Conexión fallida: " . $conn->connect_error);
    }

    // Verificar que podemos hacer una query real
    $result = $conn->query("SELECT 1 AS check_value");
    if (!$result) {
        throw new Exception("Query de verificación fallida");
    }

    $response["database"] = "connected";
    $response["db_host"]  = $db_host;
    $conn->close();

    http_response_code(200);

} catch (Exception $e) {
    $response["status"]   = "error";
    $response["database"] = "disconnected";
    $response["error"]    = $e->getMessage();

    http_response_code(503);
}

echo json_encode($response, JSON_PRETTY_PRINT);
