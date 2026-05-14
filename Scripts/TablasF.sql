-- =========================
-- ELIMINAR TABLAS SI EXISTEN
-- =========================

DROP TABLE IF EXISTS MedicamentoPrescrito CASCADE;
DROP TABLE IF EXISTS Examen CASCADE;
DROP TABLE IF EXISTS Diagnostico CASCADE;
DROP TABLE IF EXISTS Consulta CASCADE;
DROP TABLE IF EXISTS Contacto CASCADE;
DROP TABLE IF EXISTS Persona_EPS CASCADE;
DROP TABLE IF EXISTS Persona_Rol CASCADE;
DROP TABLE IF EXISTS EPS CASCADE;
DROP TABLE IF EXISTS Rol CASCADE;
DROP TABLE IF EXISTS Persona CASCADE;

-- =========================
-- TABLA ROL
-- =========================

CREATE TABLE Rol (
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50) NOT NULL,
    descripcion VARCHAR(100)
);

-- =========================
-- TABLA PERSONA
-- =========================

CREATE TABLE Persona (
    id_persona SERIAL PRIMARY KEY,
    documento VARCHAR(20) UNIQUE NOT NULL,
    primer_nombre VARCHAR(50) NOT NULL,
    segundo_nombre VARCHAR(50),
    primer_apellido VARCHAR(50) NOT NULL,
    segundo_apellido VARCHAR(50),
    direccion VARCHAR(100),
    ciudad VARCHAR(50),
    username VARCHAR(50) UNIQUE NOT NULL,
    contrasena VARCHAR(100) NOT NULL,

    -- Datos exclusivos de médicos
    tarjeta_profesional VARCHAR(50),
    especialidad VARCHAR(100)
);

-- =========================
-- TABLA PERSONA_ROL
-- =========================

CREATE TABLE Persona_Rol (
    id_persona INT,
    id_rol INT,

    PRIMARY KEY (id_persona, id_rol),

    FOREIGN KEY (id_persona)
        REFERENCES Persona(id_persona),

    FOREIGN KEY (id_rol)
        REFERENCES Rol(id_rol)
);

-- =========================
-- TABLA CONTACTO
-- =========================

CREATE TABLE Contacto (
    id_contacto SERIAL PRIMARY KEY,
    tipo VARCHAR(20) NOT NULL, -- telefono o correo
    valor VARCHAR(100) NOT NULL,
    id_persona INT NOT NULL,

    FOREIGN KEY (id_persona)
        REFERENCES Persona(id_persona)
);

-- =========================
-- TABLA EPS
-- =========================

CREATE TABLE EPS (
    id_eps SERIAL PRIMARY KEY,
    nombre_eps VARCHAR(100) NOT NULL,
    tipo_regimen VARCHAR(50),
    correo VARCHAR(100),
    telefono VARCHAR(20)
);

-- =========================
-- TABLA PERSONA_EPS
-- =========================

CREATE TABLE Persona_EPS (
    id_persona INT,
    id_eps INT,

    tipo_relacion VARCHAR(50),     -- Afiliado, Médico, Contratista
    tipo_afiliacion VARCHAR(50),   -- Contributivo, Subsidiado
    fecha_afiliacion DATE,

    PRIMARY KEY (id_persona, id_eps),

    FOREIGN KEY (id_persona)
        REFERENCES Persona(id_persona),

    FOREIGN KEY (id_eps)
        REFERENCES EPS(id_eps)
);

-- =========================
-- TABLA CONSULTA
-- =========================

CREATE TABLE Consulta (
    id_consulta SERIAL PRIMARY KEY,

    id_paciente INT NOT NULL,
    id_medico INT NOT NULL,

    fecha_consulta TIMESTAMP NOT NULL,

    FOREIGN KEY (id_paciente)
        REFERENCES Persona(id_persona),

    FOREIGN KEY (id_medico)
        REFERENCES Persona(id_persona)
);

-- =========================
-- TABLA DIAGNOSTICO
-- =========================

CREATE TABLE Diagnostico (
    id_diagnostico SERIAL PRIMARY KEY,

    id_consulta INT NOT NULL,

    descripcion TEXT,
    codigo_cie10 VARCHAR(10),

    FOREIGN KEY (id_consulta)
        REFERENCES Consulta(id_consulta)
);

-- =========================
-- TABLA EXAMEN
-- =========================

CREATE TABLE Examen (
    id_examen SERIAL PRIMARY KEY,

    id_consulta INT NOT NULL,

    tipo_examen VARCHAR(100),
    resultado TEXT,
    fecha_examen DATE,

    FOREIGN KEY (id_consulta)
        REFERENCES Consulta(id_consulta)
);

-- =========================
-- TABLA MEDICAMENTOPRESCRITO
-- =========================

CREATE TABLE MedicamentoPrescrito (
    id_medicamento SERIAL PRIMARY KEY,

    id_consulta INT NOT NULL,

    descripcion TEXT,
    frecuencia VARCHAR(50),
    duracion VARCHAR(50),
    principio_activo VARCHAR(100),
    nombre_comercial VARCHAR(100),
    dosis VARCHAR(50),

    FOREIGN KEY (id_consulta)
        REFERENCES Consulta(id_consulta)
);



-- Indices

CREATE INDEX idx_persona_rol_idrol
ON Persona_Rol(id_rol);

CREATE INDEX idx_contacto_idpersona
ON Contacto(id_persona);

CREATE INDEX idx_contacto_tipo
ON Contacto(tipo);

CREATE INDEX idx_persona_eps_ideps
ON Persona_EPS(id_eps);

CREATE INDEX idx_persona_eps_tipo_relacion
ON Persona_EPS(tipo_relacion);

CREATE INDEX idx_consulta_paciente
ON Consulta(id_paciente);

CREATE INDEX idx_consulta_medico
ON Consulta(id_medico);

CREATE INDEX idx_consulta_fecha
ON Consulta(fecha_consulta);

-- Índice compuesto para historial clínico
CREATE INDEX idx_consulta_paciente_fecha
ON Consulta(id_paciente, fecha_consulta);

CREATE INDEX idx_diagnostico_consulta
ON Diagnostico(id_consulta);

CREATE INDEX idx_diagnostico_cie10
ON Diagnostico(codigo_cie10);

CREATE INDEX idx_examen_consulta
ON Examen(id_consulta);

CREATE INDEX idx_examen_fecha
ON Examen(fecha_examen);

CREATE INDEX idx_examen_tipo
ON Examen(tipo_examen);

CREATE INDEX idx_medicamento_consulta
ON MedicamentoPrescrito(id_consulta);

CREATE INDEX idx_medicamento_principio
ON MedicamentoPrescrito(principio_activo);

CREATE INDEX idx_medicamento_nombre
ON MedicamentoPrescrito(nombre_comercial);

-- Índice para médicos
CREATE INDEX idx_persona_especialidad
ON Persona(especialidad);

CREATE INDEX idx_eps_nombre
ON EPS(nombre_eps);