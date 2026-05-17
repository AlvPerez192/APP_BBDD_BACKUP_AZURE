-- =============================================================================
-- TFG Infraestructura Multi-Cloud - Inicialización de la Base de Datos
-- =============================================================================
-- Este script se ejecuta desde el bastion contra RDS MySQL vía GitHub Actions:
--   mysql -h <RDS_ENDPOINT> -u admin -p < init.sql
--
-- Orden de creación: tablas sin FK primero, luego las que tienen FK.
-- Incluye datos de prueba para verificar el correcto funcionamiento.
-- =============================================================================

-- Crear la base de datos si no existe (idempotente)
CREATE DATABASE IF NOT EXISTS gym;
USE gym;

-- =============================================================================
-- TABLAS SIN FOREIGN KEYS (se crean primero)
-- =============================================================================

CREATE TABLE IF NOT EXISTS membresias (
    id_membresia INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL,
    precio DECIMAL(8,2) NOT NULL,
    invitaciones BOOLEAN NOT NULL,
    clase_gratis BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS clientes (
    dni_cliente VARCHAR(20) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    edad INT,
    sexo VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS empleados (
    dni_empleado VARCHAR(20) PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    sueldo DECIMAL(8,2),
    puesto ENUM('recepcionista', 'entrenador', 'limpiador') NOT NULL
);

CREATE TABLE IF NOT EXISTS salas (
    id_sala INT AUTO_INCREMENT PRIMARY KEY,
    tamaño DECIMAL(6,2),
    tipo ENUM('cardio', 'musculacion', 'estiramientos') NOT NULL
);

-- =============================================================================
-- TABLAS CON FOREIGN KEYS (dependen de las anteriores)
-- =============================================================================

-- Relación ternaria: un recepcionista vende una membresía a un cliente
CREATE TABLE IF NOT EXISTS venta_alta (
    id_venta INT AUTO_INCREMENT PRIMARY KEY,
    dni_cliente VARCHAR(20) NOT NULL,
    dni_empleado VARCHAR(20) NOT NULL,
    id_membresia INT NOT NULL,
    fecha DATE NOT NULL,

    FOREIGN KEY (dni_cliente) REFERENCES clientes(dni_cliente),
    FOREIGN KEY (dni_empleado) REFERENCES empleados(dni_empleado),
    FOREIGN KEY (id_membresia) REFERENCES membresias(id_membresia)
);

-- Relación N:M: un entrenador entrena a varios clientes y viceversa
CREATE TABLE IF NOT EXISTS entrenan (
    dni_cliente VARCHAR(20) NOT NULL,
    dni_empleado VARCHAR(20) NOT NULL,
    sesiones_restantes INT NOT NULL,

    PRIMARY KEY (dni_cliente, dni_empleado),

    FOREIGN KEY (dni_cliente) REFERENCES clientes(dni_cliente),
    FOREIGN KEY (dni_empleado) REFERENCES empleados(dni_empleado)
);

-- Relación 1:N: un limpiador limpia varias salas
CREATE TABLE IF NOT EXISTS limpian (
    dni_empleado VARCHAR(20) NOT NULL,
    id_sala INT NOT NULL,
    fecha DATE NOT NULL,

    PRIMARY KEY (dni_empleado, id_sala, fecha),

    FOREIGN KEY (dni_empleado) REFERENCES empleados(dni_empleado),
    FOREIGN KEY (id_sala) REFERENCES salas(id_sala)
);

-- Relación N:M: empleados están asignados a salas por fecha
CREATE TABLE IF NOT EXISTS estan_en (
    dni_empleado VARCHAR(20) NOT NULL,
    id_sala INT NOT NULL,
    fecha DATE NOT NULL,

    PRIMARY KEY (dni_empleado, id_sala, fecha),

    FOREIGN KEY (dni_empleado) REFERENCES empleados(dni_empleado),
    FOREIGN KEY (id_sala) REFERENCES salas(id_sala)
);

-- =============================================================================
-- DATOS DE PRUEBA
-- =============================================================================
-- Estos inserts sirven para:
--   1. Verificar que la conexión a RDS funciona correctamente
--   2. Que el formulario web tenga datos con los que trabajar
--   3. Demostrar que las relaciones FK funcionan

-- Membresías (necesarias para el formulario de inscripción)
INSERT INTO membresias (nombre, precio, invitaciones, clase_gratis) VALUES
    ('Básica', 29.99, FALSE, FALSE),
    ('Premium', 49.99, TRUE, TRUE),
    ('VIP', 79.99, TRUE, TRUE)
ON DUPLICATE KEY UPDATE nombre = VALUES(nombre);

-- Empleados (el recepcionista '11111111A' se usa por defecto en las altas)
INSERT INTO empleados (dni_empleado, nombre, sueldo, puesto) VALUES
    ('11111111A', 'Carlos García', 1800.00, 'recepcionista'),
    ('22222222B', 'Laura Martínez', 1600.00, 'recepcionista'),
    ('33333333C', 'Pedro López', 2100.00, 'entrenador'),
    ('44444444D', 'Ana Ruiz', 1500.00, 'entrenador'),
    ('55555555E', 'Miguel Torres', 1400.00, 'limpiador'),
    ('66666666F', 'Sofía Navarro', 1350.00, 'limpiador')
ON DUPLICATE KEY UPDATE nombre = VALUES(nombre);

-- Salas del gimnasio
INSERT INTO salas (tamaño, tipo) VALUES
    (30.00, 'musculacion'),
    (25.00, 'cardio'),
    (20.00, 'cardio'),
    (15.00, 'estiramientos'),
    (35.00, 'musculacion')
ON DUPLICATE KEY UPDATE tipo = VALUES(tipo);

-- Clientes de prueba (para verificar que el CRUD funciona)
INSERT INTO clientes (dni_cliente, nombre, edad, sexo) VALUES
    ('12345678A', 'Juan Pérez', 28, 'Hombre'),
    ('87654321B', 'María López', 34, 'Mujer'),
    ('11223344C', 'Alejandro Ruiz', 22, 'Hombre')
ON DUPLICATE KEY UPDATE nombre = VALUES(nombre);

-- Ventas de prueba (verifican que las FK funcionan correctamente)
INSERT INTO venta_alta (dni_cliente, dni_empleado, id_membresia, fecha) VALUES
    ('12345678A', '11111111A', 1, CURDATE()),
    ('87654321B', '22222222B', 2, CURDATE()),
    ('11223344C', '11111111A', 3, CURDATE())
ON DUPLICATE KEY UPDATE fecha = VALUES(fecha);

-- Asignación de entrenadores a clientes
INSERT INTO entrenan (dni_cliente, dni_empleado, sesiones_restantes) VALUES
    ('12345678A', '33333333C', 10),
    ('87654321B', '44444444D', 5)
ON DUPLICATE KEY UPDATE sesiones_restantes = VALUES(sesiones_restantes);

-- Limpieza de salas
INSERT INTO limpian (dni_empleado, id_sala, fecha) VALUES
    ('55555555E', 1, CURDATE()),
    ('66666666F', 2, CURDATE()),
    ('55555555E', 3, CURDATE())
ON DUPLICATE KEY UPDATE fecha = VALUES(fecha);

-- Empleados asignados a salas
INSERT INTO estan_en (dni_empleado, id_sala, fecha) VALUES
    ('33333333C', 1, CURDATE()),
    ('44444444D', 2, CURDATE()),
    ('33333333C', 5, CURDATE())
ON DUPLICATE KEY UPDATE fecha = VALUES(fecha);
