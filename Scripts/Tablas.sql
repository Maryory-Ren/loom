-- Tablas
CREATE TABLE Rol (
    id_rol SERIAL PRIMARY KEY,
    nombre_rol VARCHAR(50),
    descripcion VARCHAR(100)
);

CREATE TABLE Usuario (
    id_usuario SERIAL PRIMARY KEY,
    documento VARCHAR(20),
    primer_nombre VARCHAR(50),
    segundo_nombre VARCHAR(50),
    primer_apellido VARCHAR(50),
    segundo_apellido VARCHAR(50),
    direccion VARCHAR(100),
    ciudad VARCHAR(50),
    username VARCHAR(50),
    contrasena VARCHAR(100),
    id_rol INT,
    FOREIGN KEY (id_rol) REFERENCES Rol(id_rol)
);

CREATE TABLE Contacto (
    id_contacto SERIAL PRIMARY KEY,
    tipo VARCHAR(20), -- telefono o correo
    valor VARCHAR(100),
    id_usuario INT,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)
);

CREATE TABLE EPS (
    id_eps SERIAL PRIMARY KEY,
    nombre_eps VARCHAR(100),
    tipo_regimen VARCHAR(50),
    direccion VARCHAR(100),
    correo VARCHAR(100),
    telefono VARCHAR(20)
);

CREATE TABLE Paciente (
    id_paciente SERIAL PRIMARY KEY,
    id_usuario INT,
    id_eps INT,
    tipo_afiliacion VARCHAR(50),
    fecha_afiliacion DATE,
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_eps) REFERENCES EPS(id_eps)
);

CREATE TABLE Medico (
    id_medico SERIAL PRIMARY KEY,
    id_usuario INT,
    tarjeta_profesional VARCHAR(50),
    especialidad VARCHAR(100),
    FOREIGN KEY (id_usuario) REFERENCES Usuario(id_usuario)
);

CREATE TABLE Medico_EPS (
    id_medico INT,
    id_eps INT,
    PRIMARY KEY (id_medico, id_eps),
    FOREIGN KEY (id_medico) REFERENCES Medico(id_medico),
    FOREIGN KEY (id_eps) REFERENCES EPS(id_eps)
);

CREATE TABLE Consulta (
    id_consulta SERIAL PRIMARY KEY,
    id_paciente INT,
    id_medico INT,
    fecha_consulta TIMESTAMP,
    FOREIGN KEY (id_paciente) REFERENCES Paciente(id_paciente),
    FOREIGN KEY (id_medico) REFERENCES Medico(id_medico)
);

CREATE TABLE Diagnostico (
    id_diagnostico SERIAL PRIMARY KEY,
    id_consulta INT,
    descripcion TEXT,
    codigo_cie10 VARCHAR(10),
    FOREIGN KEY (id_consulta) REFERENCES Consulta(id_consulta)
);

CREATE TABLE Examen (
    id_examen SERIAL PRIMARY KEY,
    id_consulta INT,
    tipo_examen VARCHAR(100),
    resultado TEXT,
    fecha_examen DATE,
    FOREIGN KEY (id_consulta) REFERENCES Consulta(id_consulta)
);

CREATE TABLE MedicamentoPrescrito (
    id_medicamento SERIAL PRIMARY KEY,
    id_consulta INT,
    descripcion TEXT,
    frecuencia VARCHAR(50),
    duracion VARCHAR(50),
    principio_activo VARCHAR(100),
    nombre_comercial VARCHAR(100),
    dosis VARCHAR(50),
    FOREIGN KEY (id_consulta) REFERENCES Consulta(id_consulta)
);


