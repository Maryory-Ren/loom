-- ROCEDIMIENTOS ALMACENADOS Y TRIGGERS
-- SECCIÓN 1: TABLAS DE APOYO

CREATE TABLE IF NOT EXISTS AuditoriaAcceso (
    id_auditoria   SERIAL PRIMARY KEY,
    id_persona     INT            NOT NULL,  -- quien realiza la acción (médico)
    id_paciente    INT            NOT NULL,  -- persona que recibe la consulta
    fecha_acceso   TIMESTAMP      NOT NULL DEFAULT NOW(),
    accion         VARCHAR(50)    NOT NULL,
    detalle        TEXT,
    FOREIGN KEY (id_persona)  REFERENCES Persona(id_persona),
    FOREIGN KEY (id_paciente) REFERENCES Persona(id_persona)
);

CREATE TABLE IF NOT EXISTS HistorialEPS (
    id_historial    SERIAL PRIMARY KEY,
    id_persona      INT          NOT NULL,  -- paciente que cambia de EPS
    id_eps_anterior INT,
    id_eps_nueva    INT          NOT NULL,
    fecha_cambio    TIMESTAMP    NOT NULL DEFAULT NOW(),
    motivo          VARCHAR(200),
    FOREIGN KEY (id_persona)      REFERENCES Persona(id_persona),
    FOREIGN KEY (id_eps_anterior) REFERENCES EPS(id_eps),
    FOREIGN KEY (id_eps_nueva)    REFERENCES EPS(id_eps)
);


-- SECCIÓN 2: PROCEDIMIENTOS ALMACENADOS

-- PROCEDIMIENTO 1: registrar_consulta_completa
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
    v_existe_paciente   INT;
    v_existe_medico     INT;
    v_medico_habilitado INT;
BEGIN
    -- 1. Validar que el paciente existe y tiene rol 'Paciente'
    SELECT COUNT(*) INTO v_existe_paciente
    FROM Persona p
    JOIN Persona_Rol pr ON p.id_persona = pr.id_persona
    JOIN Rol r          ON pr.id_rol    = r.id_rol
    WHERE p.id_persona  = p_id_paciente
      AND r.nombre_rol  = 'Paciente';

    IF v_existe_paciente = 0 THEN
        RAISE EXCEPTION
            'LOOM: La persona con ID % no existe o no tiene rol Paciente.',
            p_id_paciente;
    END IF;

    -- 2. Validar que el médico existe y tiene rol 'Medico'
    SELECT COUNT(*) INTO v_existe_medico
    FROM Persona p
    JOIN Persona_Rol pr ON p.id_persona = pr.id_persona
    JOIN Rol r          ON pr.id_rol    = r.id_rol
    WHERE p.id_persona  = p_id_medico
      AND r.nombre_rol  = 'Medico';

    IF v_existe_medico = 0 THEN
        RAISE EXCEPTION
            'LOOM: La persona con ID % no existe o no tiene rol Medico.',
            p_id_medico;
    END IF;

    -- 3. Validar que el médico comparte al menos una EPS con el paciente
    --    Médico → Persona_EPS (tipo_relacion = 'Medico')
    --    Paciente → Persona_EPS (tipo_relacion = 'Afiliado')
    SELECT COUNT(*) INTO v_medico_habilitado
    FROM Persona_EPS pe_medico
    JOIN Persona_EPS pe_paciente
        ON pe_medico.id_eps      = pe_paciente.id_eps
    WHERE pe_medico.id_persona   = p_id_medico
      AND pe_medico.tipo_relacion = 'Medico'
      AND pe_paciente.id_persona  = p_id_paciente
      AND pe_paciente.tipo_relacion = 'Afiliado';

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

    -- 7. Registrar el medicamento prescrito (si se proporcionó)
    IF p_desc_medicamento IS NOT NULL THEN
        INSERT INTO MedicamentoPrescrito
            (id_consulta, descripcion, frecuencia, duracion,
             principio_activo, nombre_comercial, dosis)
        VALUES
            (p_id_consulta, p_desc_medicamento, p_frecuencia, p_duracion,
             p_principio_activo, p_nombre_comercial, p_dosis);
    END IF;

    -- 8. Registrar auditoría
    INSERT INTO AuditoriaAcceso (id_persona, id_paciente, accion, detalle)
    VALUES (
        p_id_medico,
        p_id_paciente,
        'REGISTRO_CONSULTA',
        FORMAT(
            'Consulta #%s registrada. Diagnóstico: %s (%s)',
            p_id_consulta, p_desc_diagnostico, p_codigo_cie10
        )
    );

    RAISE NOTICE
        'LOOM: Consulta #% registrada exitosamente para el paciente %.',
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
    v_es_paciente     INT;
BEGIN
    -- 1. Verificar que la persona tiene rol Paciente
    SELECT COUNT(*) INTO v_es_paciente
    FROM Persona_Rol pr
    JOIN Rol r ON pr.id_rol = r.id_rol
    WHERE pr.id_persona = p_id_paciente
      AND r.nombre_rol  = 'Paciente';

    IF v_es_paciente = 0 THEN
        RAISE EXCEPTION
            'LOOM: La persona con ID % no existe o no tiene rol Paciente.',
            p_id_paciente;
    END IF;

    -- 2. Obtener EPS actual del paciente (afiliación vigente)
    SELECT pe.id_eps, e.nombre_eps
    INTO   v_id_eps_anterior, v_nombre_eps_ant
    FROM   Persona_EPS pe
    JOIN   EPS         e ON e.id_eps = pe.id_eps
    WHERE  pe.id_persona    = p_id_paciente
      AND  pe.tipo_relacion = 'Afiliado'
    LIMIT 1;

    IF v_id_eps_anterior IS NULL THEN
        RAISE EXCEPTION
            'LOOM: El paciente ID % no tiene una EPS afiliada actualmente.',
            p_id_paciente;
    END IF;

    -- 3. Validar que la nueva EPS existe
    SELECT nombre_eps INTO v_nombre_eps_nva
    FROM EPS WHERE id_eps = p_id_eps_nueva;

    IF v_nombre_eps_nva IS NULL THEN
        RAISE EXCEPTION
            'LOOM: La EPS con ID % no existe en el sistema.',
            p_id_eps_nueva;
    END IF;

    -- 4. Registrar historial antes del cambio
    INSERT INTO HistorialEPS (id_persona, id_eps_anterior, id_eps_nueva, motivo)
    VALUES (p_id_paciente, v_id_eps_anterior, p_id_eps_nueva, p_motivo);

    -- 5. Actualizar EPS y fecha de afiliación en Persona_EPS
    UPDATE Persona_EPS
    SET    id_eps           = p_id_eps_nueva,
           fecha_afiliacion = CURRENT_DATE
    WHERE  id_persona    = p_id_paciente
      AND  tipo_relacion = 'Afiliado';

    RAISE NOTICE
        'LOOM: Paciente % trasladado de % → %. Historia clínica preservada.',
        p_id_paciente, v_nombre_eps_ant, v_nombre_eps_nva;

END;
$$;


-- SECCIÓN 3: TRIGGERS
-- TRIGGER 1: Auditoría automática al insertar una consulta
CREATE OR REPLACE FUNCTION fn_auditoria_nueva_consulta()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- El médico (id_medico) es directamente una Persona
    INSERT INTO AuditoriaAcceso (id_persona, id_paciente, accion, detalle)
    VALUES (
        NEW.id_medico,
        NEW.id_paciente,
        'NUEVA_CONSULTA',
        FORMAT(
            'Consulta #%s creada el %s por médico ID %s para paciente ID %s.',
            NEW.id_consulta,
            NEW.fecha_consulta,
            NEW.id_medico,
            NEW.id_paciente
        )
    );

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_auditoria_nueva_consulta
AFTER INSERT ON Consulta
FOR EACH ROW
EXECUTE FUNCTION fn_auditoria_nueva_consulta();


-- TRIGGER 2: Validar que el médico tiene convenio con
--            al menos una EPS antes de registrar la consulta

CREATE OR REPLACE FUNCTION fn_validar_medico_activo()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_convenios    INT;
    v_especialidad VARCHAR(100);
    v_es_medico    INT;
BEGIN
    -- Verificar que la persona tiene rol Médico
    SELECT COUNT(*) INTO v_es_medico
    FROM Persona_Rol pr
    JOIN Rol r ON pr.id_rol = r.id_rol
    WHERE pr.id_persona = NEW.id_medico
      AND r.nombre_rol  = 'Medico';

    IF v_es_medico = 0 THEN
        RAISE EXCEPTION
            'LOOM: La persona con ID % no tiene rol Medico y no puede registrar consultas.',
            NEW.id_medico;
    END IF;

    -- Contar EPS con las que el médico tiene convenio
    SELECT COUNT(*), MAX(p.especialidad)
    INTO   v_convenios, v_especialidad
    FROM   Persona_EPS pe
    JOIN   Persona     p ON p.id_persona = pe.id_persona
    WHERE  pe.id_persona    = NEW.id_medico
      AND  pe.tipo_relacion = 'Medico';

    IF v_convenios = 0 THEN
        RAISE EXCEPTION
            'LOOM: El médico (ID %) no tiene convenio con ninguna EPS. '
            'No puede registrar consultas hasta que sea habilitado.',
            NEW.id_medico;
    END IF;

    RAISE NOTICE
        'LOOM: Médico ID % (%) validado. Convenios activos: %.',
        NEW.id_medico, v_especialidad, v_convenios;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_validar_medico_activo_consulta
BEFORE INSERT ON Consulta
FOR EACH ROW
EXECUTE FUNCTION fn_validar_medico_activo();


-- TRIGGER 3: Registrar historial automático cuando
--            cambia la EPS de un paciente en Persona_EPS

CREATE OR REPLACE FUNCTION fn_historial_cambio_eps()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Solo actuar si cambió el id_eps y es una fila de tipo Afiliado
    IF OLD.id_eps IS DISTINCT FROM NEW.id_eps
       AND NEW.tipo_relacion = 'Afiliado' THEN

        INSERT INTO HistorialEPS
            (id_persona, id_eps_anterior, id_eps_nueva, motivo)
        VALUES (
            NEW.id_persona,
            OLD.id_eps,
            NEW.id_eps,
            'Cambio detectado automáticamente por el sistema LOOM.'
        );

        RAISE NOTICE
            'LOOM: Traslado de EPS registrado automáticamente. '
            'Persona ID %, EPS anterior: %, EPS nueva: %.',
            NEW.id_persona, OLD.id_eps, NEW.id_eps;
    END IF;

    RETURN NEW;
END;
$$;

-- El trigger ahora va sobre Persona_EPS (no sobre Paciente)
CREATE OR REPLACE TRIGGER trg_historial_cambio_eps
AFTER UPDATE OF id_eps ON Persona_EPS
FOR EACH ROW
EXECUTE FUNCTION fn_historial_cambio_eps();


-- SECCIÓN 4: EJEMPLOS DE USO
-- Ejemplo 1: Registrar una consulta completa

-- Sincroniza la secuencia al valor máximo actual de id_consulta
SELECT setval(
    pg_get_serial_sequence('Consulta', 'id_consulta'),
    (SELECT MAX(id_consulta) FROM Consulta)
);

CALL registrar_consulta_completa(
    11,                                             -- id_paciente (Persona con rol Paciente)
    1,                                              -- id_medico   (Persona con rol Medico)
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
    NULL                                            -- OUT: id_consulta generado
);


-- Ejemplo 2: Cambiar EPS del paciente 11 a la EPS con ID 3
CALL cambiar_eps_paciente(11, 3, 'Traslado voluntario por cambio de empleador');


-- Ejemplo 3: Verificar auditoría generada automáticamente
SELECT
    aa.id_auditoria,
    pm.primer_nombre || ' ' || pm.primer_apellido  AS medico,
    r.nombre_rol,
    pp.primer_nombre || ' ' || pp.primer_apellido  AS paciente,
    aa.accion,
    aa.fecha_acceso,
    aa.detalle
FROM   AuditoriaAcceso aa
JOIN   Persona pm ON pm.id_persona = aa.id_persona   -- médico que actuó
JOIN   Persona pp ON pp.id_persona = aa.id_paciente  -- paciente afectado
JOIN   Persona_Rol pr ON pr.id_persona = aa.id_persona
JOIN   Rol r          ON r.id_rol      = pr.id_rol
ORDER  BY aa.fecha_acceso DESC
LIMIT  20;


-- Ejemplo 4: Ver historial de cambios de EPS de un paciente
SELECT
    he.id_historial,
    p.primer_nombre || ' ' || p.primer_apellido AS paciente,
    e_ant.nombre_eps  AS eps_anterior,
    e_nva.nombre_eps  AS eps_nueva,
    he.fecha_cambio,
    he.motivo
FROM   HistorialEPS he
JOIN   Persona  p     ON p.id_persona = he.id_persona
LEFT JOIN EPS e_ant   ON e_ant.id_eps = he.id_eps_anterior
JOIN      EPS e_nva   ON e_nva.id_eps = he.id_eps_nueva
WHERE  he.id_persona = 11
ORDER  BY he.fecha_cambio DESC;