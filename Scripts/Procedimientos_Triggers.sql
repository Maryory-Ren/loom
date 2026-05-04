-- ROCEDIMIENTOS ALMACENADOS Y TRIGGERS

--  SECCIÓN 1: TABLAS DE APOYO

CREATE TABLE IF NOT EXISTS AuditoriaAcceso (
    id_auditoria   SERIAL PRIMARY KEY,
    id_usuario     INT            NOT NULL,
    id_paciente    INT            NOT NULL,
    fecha_acceso   TIMESTAMP      NOT NULL DEFAULT NOW(),
    accion         VARCHAR(50)    NOT NULL,   
    detalle        TEXT,
    FOREIGN KEY (id_usuario)  REFERENCES Usuario(id_usuario),
    FOREIGN KEY (id_paciente) REFERENCES Paciente(id_paciente)
);

CREATE TABLE IF NOT EXISTS HistorialEPS (
    id_historial    SERIAL PRIMARY KEY,
    id_paciente     INT          NOT NULL,
    id_eps_anterior INT,
    id_eps_nueva    INT          NOT NULL,
    fecha_cambio    TIMESTAMP    NOT NULL DEFAULT NOW(),
    motivo          VARCHAR(200),
    FOREIGN KEY (id_paciente)     REFERENCES Paciente(id_paciente),
    FOREIGN KEY (id_eps_anterior) REFERENCES EPS(id_eps),
    FOREIGN KEY (id_eps_nueva)    REFERENCES EPS(id_eps)
);


--  SECCIÓN 2: PROCEDIMIENTOS ALMACENADOS

CREATE OR REPLACE PROCEDURE registrar_consulta_completa(
    IN  p_id_paciente       INT,
    IN  p_id_medico         INT,
    IN  p_fecha_consulta    TIMESTAMP,
    IN  p_desc_diagnostico  TEXT,
    IN  p_codigo_cie10      VARCHAR(10),
    IN  p_tipo_examen       VARCHAR(100),
    IN  p_resultado_examen  TEXT,
    IN  p_fecha_examen      DATE,
    IN  p_desc_medicamento  TEXT,
    IN  p_principio_activo  VARCHAR(100),
    IN  p_nombre_comercial  VARCHAR(100),
    IN  p_dosis             VARCHAR(50),
    IN  p_frecuencia        VARCHAR(50),
    IN  p_duracion          VARCHAR(50),
    OUT p_id_consulta       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_existe_paciente INT;
    v_existe_medico   INT;
    v_medico_habilitado INT;
BEGIN
    -- 1. Validar que el paciente existe
    SELECT COUNT(*) INTO v_existe_paciente
    FROM Paciente WHERE id_paciente = p_id_paciente;

    IF v_existe_paciente = 0 THEN
        RAISE EXCEPTION 'LOOM: El paciente con ID % no existe en el sistema.', p_id_paciente;
    END IF;

    -- 2. Validar que el médico existe
    SELECT COUNT(*) INTO v_existe_medico
    FROM Medico WHERE id_medico = p_id_medico;

    IF v_existe_medico = 0 THEN
        RAISE EXCEPTION 'LOOM: El médico con ID % no está registrado en el sistema.', p_id_medico;
    END IF;

    -- 3. Validar que el médico pertenece a la EPS del paciente
    SELECT COUNT(*) INTO v_medico_habilitado
    FROM Medico_EPS me
    JOIN Paciente   pa ON pa.id_eps = me.id_eps
    WHERE me.id_medico  = p_id_medico
      AND pa.id_paciente = p_id_paciente;

    IF v_medico_habilitado = 0 THEN
        RAISE EXCEPTION
            'LOOM: El médico (ID %) no tiene convenio con la EPS del paciente (ID %). '
            'Verifique la red de prestadores habilitados.',
            p_id_medico, p_id_paciente;
    END IF;

    -- 4. Registrar la consulta
    INSERT INTO Consulta (id_paciente, id_medico, fecha_consulta)
    VALUES (p_id_paciente, p_id_medico, p_fecha_consulta)
    RETURNING id_consulta INTO p_id_consulta;

    -- 5. Registrar el diagnóstico
    INSERT INTO Diagnostico (id_consulta, descripcion, codigo_cie10)
    VALUES (p_id_consulta, p_desc_diagnostico, p_codigo_cie10);

    -- 6. Registrar el examen (si se proporcionó)
    IF p_tipo_examen IS NOT NULL THEN
        INSERT INTO Examen (id_consulta, tipo_examen, resultado, fecha_examen)
        VALUES (p_id_consulta, p_tipo_examen, p_resultado_examen, p_fecha_examen);
    END IF;

    -- 7. Registrar el medicamento prescrito 
    IF p_desc_medicamento IS NOT NULL THEN
        INSERT INTO MedicamentoPrescrito
            (id_consulta, descripcion, frecuencia, duracion,
             principio_activo, nombre_comercial, dosis)
        VALUES
            (p_id_consulta, p_desc_medicamento, p_frecuencia, p_duracion,
             p_principio_activo, p_nombre_comercial, p_dosis);
    END IF;

    -- 8. Registrar auditoría del evento
    INSERT INTO AuditoriaAcceso (id_usuario, id_paciente, accion, detalle)
    SELECT u.id_usuario,
           p_id_paciente,
           'REGISTRO_CONSULTA',
           FORMAT('Consulta #%s registrada. Diagnóstico: %s (%s)',
                  p_id_consulta, p_desc_diagnostico, p_codigo_cie10)
    FROM Medico m
    JOIN Usuario u ON u.id_usuario = m.id_usuario
    WHERE m.id_medico = p_id_medico;

    RAISE NOTICE 'LOOM: Consulta #% registrada exitosamente para el paciente %.', 
                  p_id_consulta, p_id_paciente;

END;
$$;

-- PROCEDIMIENTO 2: cambiar_eps_paciente
CREATE OR REPLACE PROCEDURE cambiar_eps_paciente(
    IN p_id_paciente  INT,
    IN p_id_eps_nueva INT,
    IN p_motivo       VARCHAR(200)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_eps_anterior INT;
    v_nombre_eps_ant  VARCHAR(100);
    v_nombre_eps_nva  VARCHAR(100);
BEGIN
    -- 1. Obtener EPS actual del paciente
    SELECT pa.id_eps, e.nombre_eps
    INTO   v_id_eps_anterior, v_nombre_eps_ant
    FROM   Paciente pa
    JOIN   EPS      e ON e.id_eps = pa.id_eps
    WHERE  pa.id_paciente = p_id_paciente;

    IF v_id_eps_anterior IS NULL THEN
        RAISE EXCEPTION 'LOOM: Paciente con ID % no encontrado.', p_id_paciente;
    END IF;

    -- 2. Validar que la nueva EPS existe
    SELECT nombre_eps INTO v_nombre_eps_nva
    FROM EPS WHERE id_eps = p_id_eps_nueva;

    IF v_nombre_eps_nva IS NULL THEN
        RAISE EXCEPTION 'LOOM: La EPS con ID % no existe en el sistema.', p_id_eps_nueva;
    END IF;

    -- 4. Registrar historial antes del cambio
    INSERT INTO HistorialEPS (id_paciente, id_eps_anterior, id_eps_nueva, motivo)
    VALUES (p_id_paciente, v_id_eps_anterior, p_id_eps_nueva, p_motivo);

    -- 5. Actualizar la EPS y la fecha de afiliación
    UPDATE Paciente
    SET    id_eps           = p_id_eps_nueva,
           fecha_afiliacion = CURRENT_DATE
    WHERE  id_paciente = p_id_paciente;

    RAISE NOTICE 'LOOM: Paciente % trasladado de % → %. Historia clínica preservada.',
                  p_id_paciente, v_nombre_eps_ant, v_nombre_eps_nva;

END;
$$;


--  SECCIÓN 3: TRIGGERS

-- TRIGGER 1: trg_auditoria_acceso_historia

CREATE OR REPLACE FUNCTION fn_auditoria_nueva_consulta()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_usuario_medico INT;
BEGIN
  
    SELECT id_usuario INTO v_id_usuario_medico
    FROM Medico
    WHERE id_medico = NEW.id_medico;

    INSERT INTO AuditoriaAcceso (id_usuario, id_paciente, accion, detalle)
    VALUES (
        v_id_usuario_medico,
        NEW.id_paciente,
        'NUEVA_CONSULTA',
        FORMAT('Consulta #%s creada el %s por médico ID %s para paciente ID %s.',
               NEW.id_consulta,
               NEW.fecha_consulta,
               NEW.id_medico,
               NEW.id_paciente)
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_auditoria_nueva_consulta
AFTER INSERT ON Consulta
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria_nueva_consulta();


-- TRIGGER 2: trg_validar_medico_activo_consulta

CREATE OR REPLACE FUNCTION fn_validar_medico_activo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_convenios INT;
    v_especialidad VARCHAR(100);
BEGIN
   
    SELECT COUNT(*), m.especialidad
    INTO   v_convenios, v_especialidad
    FROM   Medico_EPS me
    JOIN   Medico     m ON m.id_medico = me.id_medico
    WHERE  me.id_medico = NEW.id_medico
    GROUP BY m.especialidad;

    IF v_convenios = 0 THEN
        RAISE EXCEPTION
            'LOOM: El médico (ID %) no tiene convenio con ninguna EPS. '
            'No puede registrar consultas hasta que sea habilitado.',
            NEW.id_medico;
    END IF;

    RAISE NOTICE 'LOOM: Médico ID % (%) validado. Convenios activos: %.',
                  NEW.id_medico, v_especialidad, v_convenios;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_validar_medico_activo_consulta
BEFORE INSERT ON Consulta
FOR EACH ROW
EXECUTE FUNCTION fn_validar_medico_activo();


-- TRIGGER 3: trg_historial_cambio_eps

CREATE OR REPLACE FUNCTION fn_historial_cambio_eps()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.id_eps IS DISTINCT FROM NEW.id_eps THEN
        INSERT INTO HistorialEPS (id_paciente, id_eps_anterior, id_eps_nueva, motivo)
        VALUES (
            NEW.id_paciente,
            OLD.id_eps,
            NEW.id_eps,
            'Cambio detectado automáticamente por el sistema LOOM.'
        );

        RAISE NOTICE 'LOOM: Traslado de EPS registrado automáticamente. Paciente ID %, EPS anterior: %, EPS nueva: %.',
                      NEW.id_paciente, OLD.id_eps, NEW.id_eps;
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_historial_cambio_eps
AFTER UPDATE OF id_eps ON Paciente
FOR EACH ROW
EXECUTE FUNCTION fn_historial_cambio_eps();


--  SECCIÓN 4: EJEMPLOS DE USO

-- Ejemplo 1: Registrar consulta completa 

CALL registrar_consulta_completa(
    1,                                         
    1,                                         
    '2025-06-01 09:00:00',                     
    'Hipertensión arterial en seguimiento',  
    'I10',                                    
    'Tensión arterial',                       
    'PA: 135/85 mmHg. Mejoría respecto control anterior.', 
    '2025-06-01',                              
    'Antihipertensivo ajuste de dosis',         
    'Losartán',                                
    'Cozaar',                                   
    '100 mg',                                  
    'Cada 24 horas',                            
    '6 meses',                                
    NULL                                       
);


-- Ejemplo 2: Cambiar EPS del paciente 1 a Sanitas 

CALL cambiar_eps_paciente(1, 3, 'Traslado voluntario por cambio de empleador');


-- Ejemplo 3: Verificar auditoría generada automáticamente

SELECT aa.id_auditoria,
       u.primer_nombre || ' ' || u.primer_apellido AS usuario,
       r.nombre_rol,
       aa.id_paciente,
       aa.accion,
       aa.fecha_acceso,
       aa.detalle
FROM   AuditoriaAcceso aa
JOIN   Usuario          u ON u.id_usuario = aa.id_usuario
JOIN   Rol              r ON r.id_rol     = u.id_rol
ORDER  BY aa.fecha_acceso DESC
LIMIT  20;


-- Ejemplo 4: Ver historial de cambios de EPS de un paciente

SELECT he.id_historial,
       he.id_paciente,
       e_ant.nombre_eps  AS eps_anterior,
       e_nva.nombre_eps  AS eps_nueva,
       he.fecha_cambio,
       he.motivo
FROM   HistorialEPS he
LEFT JOIN EPS e_ant ON e_ant.id_eps = he.id_eps_anterior
JOIN      EPS e_nva ON e_nva.id_eps = he.id_eps_nueva
WHERE  he.id_paciente = 1
ORDER  BY he.fecha_cambio DESC;

