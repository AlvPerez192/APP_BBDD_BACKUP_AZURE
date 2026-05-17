<?php
$mensaje = "";
$tipo = "";

$db_host = getenv("DB_HOST");
$db_user = getenv("DB_USER");
$db_password = getenv("DB_PASSWORD");
$db_name = getenv("DB_NAME");
$db_port = getenv("DB_PORT") ?: 3306;

if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $dni_cliente = $_POST["dni_cliente"];
    $nombre = $_POST["nombre"];
    $edad = $_POST["edad"];
    $sexo = $_POST["sexo"];
    $id_membresia = $_POST["id_membresia"];

    $dni_empleado = "11111111A";

    $conexion = new mysqli($db_host, $db_user, $db_password, $db_name, $db_port);

    if ($conexion->connect_error) {
        $mensaje = "No se ha podido conectar con la base de datos. Detalle técnico: " . $conexion->connect_error;
        $tipo = "error";
    } else {
        try {
            $conexion->begin_transaction();

            $stmt_cliente = $conexion->prepare(
                "INSERT INTO clientes (dni_cliente, nombre, edad, sexo)
                 VALUES (?, ?, ?, ?)"
            );
            $stmt_cliente->bind_param("ssis", $dni_cliente, $nombre, $edad, $sexo);
            $stmt_cliente->execute();

            $stmt_venta = $conexion->prepare(
                "INSERT INTO venta_alta (dni_cliente, dni_empleado, id_membresia, fecha)
                 VALUES (?, ?, ?, CURDATE())"
            );
            $stmt_venta->bind_param("ssi", $dni_cliente, $dni_empleado, $id_membresia);
            $stmt_venta->execute();

            $conexion->commit();

            $mensaje = "Inscripción completada correctamente. El cliente ha sido registrado en la base de datos.";
            $tipo = "ok";

            $stmt_cliente->close();
            $stmt_venta->close();
        } catch (Exception $e) {
            $conexion->rollback();
            $mensaje = "No se ha podido guardar la inscripción. Detalle técnico: " . $e->getMessage();
            $tipo = "error";
        }

        $conexion->close();
    }
}
?>

<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Inscripción Gimnasio | Área de Altas</title>
    <style>
        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            min-height: 100vh;
            font-family: Arial, Helvetica, sans-serif;
            background:
                linear-gradient(rgba(10, 15, 25, 0.82), rgba(10, 15, 25, 0.82)),
                linear-gradient(135deg, #111827, #1f2937, #374151);
            color: #111827;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 40px 20px;
        }

        .page-wrapper {
            width: 100%;
            max-width: 1050px;
            display: grid;
            grid-template-columns: 1fr 1.1fr;
            background: #ffffff;
            border-radius: 22px;
            overflow: hidden;
            box-shadow: 0 25px 70px rgba(0, 0, 0, 0.35);
        }

        .info-panel {
            background: linear-gradient(160deg, #111827, #1f2937);
            color: white;
            padding: 48px 42px;
            display: flex;
            flex-direction: column;
            justify-content: space-between;
        }

        .brand {
            margin-bottom: 40px;
        }

        .brand-badge {
            display: inline-block;
            background: rgba(255, 255, 255, 0.12);
            border: 1px solid rgba(255, 255, 255, 0.22);
            color: #e5e7eb;
            padding: 8px 14px;
            border-radius: 999px;
            font-size: 13px;
            letter-spacing: 0.4px;
            margin-bottom: 22px;
        }

        .info-panel h1 {
            font-size: 38px;
            line-height: 1.1;
            margin: 0 0 18px;
        }

        .info-panel p {
            color: #d1d5db;
            line-height: 1.6;
            margin: 0;
            font-size: 15px;
        }

        .features {
            margin-top: 35px;
            display: grid;
            gap: 16px;
        }

        .feature {
            display: flex;
            gap: 12px;
            align-items: flex-start;
            color: #e5e7eb;
            font-size: 14px;
        }

        .feature-icon {
            width: 26px;
            height: 26px;
            min-width: 26px;
            border-radius: 50%;
            background: #22c55e;
            color: #052e16;
            font-weight: bold;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .tech-note {
            margin-top: 40px;
            padding: 16px;
            border-radius: 14px;
            background: rgba(255, 255, 255, 0.08);
            border: 1px solid rgba(255, 255, 255, 0.14);
            color: #cbd5e1;
            font-size: 13px;
            line-height: 1.5;
        }

        .form-panel {
            padding: 48px 46px;
            background: #f9fafb;
        }

        .form-header {
            margin-bottom: 28px;
        }

        .form-header h2 {
            margin: 0 0 10px;
            font-size: 28px;
            color: #111827;
        }

        .form-header p {
            margin: 0;
            color: #6b7280;
            font-size: 15px;
            line-height: 1.5;
        }

        .alert {
            padding: 14px 16px;
            border-radius: 12px;
            margin-bottom: 22px;
            font-size: 14px;
            line-height: 1.5;
        }

        .ok {
            background: #ecfdf5;
            color: #065f46;
            border: 1px solid #a7f3d0;
            font-weight: bold;
        }

        .error {
            background: #fef2f2;
            color: #991b1b;
            border: 1px solid #fecaca;
            font-weight: bold;
        }

        form {
            display: grid;
            gap: 18px;
        }

        .form-group {
            display: flex;
            flex-direction: column;
        }

        .form-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 18px;
        }

        label {
            font-size: 14px;
            font-weight: bold;
            color: #374151;
            margin-bottom: 8px;
        }

        input, select {
            width: 100%;
            padding: 13px 14px;
            border: 1px solid #d1d5db;
            border-radius: 12px;
            font-size: 15px;
            color: #111827;
            background: white;
            outline: none;
            transition: border-color 0.2s, box-shadow 0.2s;
        }

        input:focus, select:focus {
            border-color: #2563eb;
            box-shadow: 0 0 0 4px rgba(37, 99, 235, 0.12);
        }

        input::placeholder {
            color: #9ca3af;
        }

        .help-text {
            margin-top: 6px;
            font-size: 12px;
            color: #6b7280;
        }

        button {
            margin-top: 8px;
            width: 100%;
            padding: 15px;
            border: none;
            border-radius: 12px;
            background: linear-gradient(135deg, #2563eb, #1d4ed8);
            color: white;
            font-size: 16px;
            font-weight: bold;
            cursor: pointer;
            transition: transform 0.15s, box-shadow 0.15s, background 0.15s;
            box-shadow: 0 10px 20px rgba(37, 99, 235, 0.22);
        }

        button:hover {
            transform: translateY(-1px);
            box-shadow: 0 14px 24px rgba(37, 99, 235, 0.28);
            background: linear-gradient(135deg, #1d4ed8, #1e40af);
        }

        button:active {
            transform: translateY(0);
        }

        .nota {
            margin-top: 22px;
            padding: 14px 16px;
            border-radius: 12px;
            background: #eef2ff;
            color: #3730a3;
            font-size: 13px;
            line-height: 1.5;
            border: 1px solid #c7d2fe;
        }

        .footer-text {
            margin-top: 18px;
            color: #9ca3af;
            font-size: 12px;
            text-align: center;
        }

        @media (max-width: 850px) {
            .page-wrapper {
                grid-template-columns: 1fr;
            }

            .info-panel {
                padding: 34px 28px;
            }

            .info-panel h1 {
                font-size: 30px;
            }

            .form-panel {
                padding: 34px 28px;
            }
        }

        @media (max-width: 520px) {
            .form-row {
                grid-template-columns: 1fr;
            }

            body {
                padding: 20px 12px;
            }
        }
    </style>
</head>
<body>
    <main class="page-wrapper">
        <section class="info-panel">
            <div>
                <div class="brand">
        
                    <h1>¡Apúntate a nuestro gimnasio!</h1>
                    <p>
                        Disfrutarás de la mejor experiencia como socio, con máquinas de última generación y auténticos profesionales a tu lado.
                    </p>
                </div>

                <div class="features">
                    <div class="feature">
                        <div class="feature-icon">✓</div>
                        <div>Cambios visibles</strong>.</div>
                    </div>
                    <div class="feature">
                        <div class="feature-icon">✓</div>
                        <div>Instalaciones nuevas</div>
                    </div>
                    <div class="feature">
                        <div class="feature-icon">✓</div>
                        <div>Profesionales a tu lado</div>
                    </div>
                </div>
            </div>

            <div class="tech-note">
                Infraestructura basada en AWS y GitHub creada por Álvaro Pérez y Diego Cárdenas como TFG para 2ASIR.
            </div>
        </section>

        <section class="form-panel">
            <div class="form-header">
                <h2>Nueva inscripción</h2>
                <p>
                    Introduce tus datos y selecciona la membresía que mejor se amolde a tus necesidades.
                    Al enviar el formulario, el alta quedará registrada automáticamente.
                </p>
            </div>

            <?php if ($mensaje !== ""): ?>
                <div class="alert <?php echo $tipo; ?>">
                    <?php echo htmlspecialchars($mensaje); ?>
                </div>
            <?php endif; ?>

            <form method="POST">
                <div class="form-group">
                    <label for="dni_cliente">DNI</label>
                    <input
                        type="text"
                        id="dni_cliente"
                        name="dni_cliente"
                        maxlength="20"
                        placeholder="Ejemplo: 12345678A"
                        required
                    >
                    
                </div>

                <div class="form-group">
                    <label for="nombre">Nombre completo</label>
                    <input
                        type="text"
                        id="nombre"
                        name="nombre"
                        placeholder="Ejemplo: Laura Sánchez Martínez"
                        required
                    >
                </div>

                <div class="form-row">
                    <div class="form-group">
                        <label for="edad">Edad</label>
                        <input
                            type="number"
                            id="edad"
                            name="edad"
                            min="0"
                            max="120"
                            placeholder="Ejemplo: 28"
                        >
                    </div>

                    <div class="form-group">
                        <label for="sexo">Sexo</label>
                        <select id="sexo" name="sexo">
                            <option value="Hombre">Hombre</option>
                            <option value="Mujer">Mujer</option>
                            <option value="Otro">Otro</option>
                        
                        </select>
                    </div>
                </div>

                <div class="form-group">
                    <label for="id_membresia">Tipo de membresía</label>
                    <select id="id_membresia" name="id_membresia" required>
                        <option value="1">Básica — 29.99€ / mes</option>
                        <option value="2">Premium — 49.99€ / mes</option>
                        <option value="3">VIP — 79.99€ / mes</option>
                    </select>
                    <span class="help-text">La membresía seleccionada se asociará al alta.</span>
                </div>

                <button type="submit">Registrar inscripción</button>
            </form>

            <p class="nota">
                El alta se almacena en las tablas <strong>clientes</strong> y <strong>venta_alta</strong>
                de la base de datos RDS MySQL.
            </p>


        </section>
    </main>
</body>
</html>