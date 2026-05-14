
-- CONSULTAS
-- 1. Historial completo de consultas de un paciente
--    por documento de identidad
SELECT
    p.documento,

    p.primer_nombre || ' ' || p.primer_apellido
        AS paciente,

    eps.nombre_eps,

    c.id_consulta,
    c.fecha_consulta,

    m.primer_nombre || ' ' || m.primer_apellido
        AS medico,

    m.especialidad,

    -- Diagnósticos agrupados
    STRING_AGG(
        DISTINCT d.descripcion,
        ' | '
    ) AS diagnosticos,

    STRING_AGG(
        DISTINCT d.codigo_cie10,
        ' | '
    ) AS codigos_cie10,

    -- Exámenes agrupados
    STRING_AGG(
        DISTINCT e.tipo_examen,
        ' | '
    ) AS examenes,

    STRING_AGG(
        DISTINCT e.resultado,
        ' | '
    ) AS resultados_examenes,

    -- Medicamentos agrupados
    STRING_AGG(
        DISTINCT mp.nombre_comercial,
        ' | '
    ) AS medicamentos,

    STRING_AGG(
        DISTINCT mp.principio_activo,
        ' | '
    ) AS principios_activos,

    STRING_AGG(
        DISTINCT mp.dosis,
        ' | '
    ) AS dosis,

    STRING_AGG(
        DISTINCT mp.frecuencia,
        ' | '
    ) AS frecuencias,

    STRING_AGG(
        DISTINCT mp.duracion,
        ' | '
    ) AS duraciones

FROM Consulta c

-- Paciente
JOIN Persona p
    ON c.id_paciente = p.id_persona

-- EPS del paciente
JOIN Persona_EPS pe
    ON p.id_persona = pe.id_persona
   AND pe.tipo_relacion = 'Afiliado'

JOIN EPS eps
    ON pe.id_eps = eps.id_eps

-- Médico
JOIN Persona m
    ON c.id_medico = m.id_persona

-- Relaciones 1:N
LEFT JOIN Diagnostico d
    ON c.id_consulta = d.id_consulta

LEFT JOIN Examen e
    ON c.id_consulta = e.id_consulta

LEFT JOIN MedicamentoPrescrito mp
    ON c.id_consulta = mp.id_consulta

WHERE p.documento = '20001011'

GROUP BY
    p.documento,
    paciente,
    eps.nombre_eps,
    c.id_consulta,
    c.fecha_consulta,
    medico,
    m.especialidad

ORDER BY c.fecha_consulta DESC;


-- 2. EPS con mayor número de pacientes afiliados
SELECT
    eps.nombre_eps,
    COUNT(pe.id_persona) AS total_pacientes

FROM EPS eps

-- Pacientes afiliados via Persona_EPS
JOIN Persona_EPS pe
    ON eps.id_eps = pe.id_eps
   AND pe.tipo_relacion = 'Afiliado'

-- Confirmar que esa persona tiene rol Paciente
JOIN Persona_Rol pr
    ON pe.id_persona = pr.id_persona

JOIN Rol r
    ON pr.id_rol = r.id_rol
   AND r.nombre_rol = 'Paciente'

GROUP BY eps.id_eps, eps.nombre_eps

HAVING COUNT(pe.id_persona) = (
    SELECT MAX(total)
    FROM (
        SELECT COUNT(pe2.id_persona) AS total
        FROM Persona_EPS pe2
        JOIN Persona_Rol pr2
            ON pe2.id_persona = pr2.id_persona
        JOIN Rol r2
            ON pr2.id_rol = r2.id_rol
           AND r2.nombre_rol = 'Paciente'
        WHERE pe2.tipo_relacion = 'Afiliado'
        GROUP BY pe2.id_eps
    ) sub
);


-- 3. Diagnóstico más frecuente por cada EPS
SELECT * FROM (
    SELECT
        eps.nombre_eps,
        d.codigo_cie10,
        d.descripcion,
        COUNT(*)    AS total_casos,
        ROW_NUMBER() OVER (
            PARTITION BY eps.id_eps
            ORDER BY COUNT(*) DESC
        ) AS fila

    FROM EPS eps

    -- Pacientes afiliados a esa EPS
    JOIN Persona_EPS pe
        ON eps.id_eps = pe.id_eps
       AND pe.tipo_relacion = 'Afiliado'

    -- Solo personas con rol Paciente
    JOIN Persona_Rol pr
        ON pe.id_persona = pr.id_persona

    JOIN Rol r
        ON pr.id_rol = r.id_rol
       AND r.nombre_rol = 'Paciente'

    -- Consultas de ese paciente
    JOIN Consulta c
        ON pe.id_persona = c.id_paciente

    -- Diagnósticos de esas consultas
    JOIN Diagnostico d
        ON c.id_consulta = d.id_consulta

    GROUP BY
        eps.id_eps,
        eps.nombre_eps,
        d.codigo_cie10,
        d.descripcion

) diagnosticos_eps
WHERE fila = 1;