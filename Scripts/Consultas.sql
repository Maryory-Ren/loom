-- Consultas 
-- 1. Historial clinico de un paciente en especifico
SELECT 
u.documento,
u.primer_nombre || ' ' || u.primer_apellido AS paciente,
c.id_consulta,
c.fecha_consulta,
d.descripcion AS diagnostico,
d.codigo_cie10,
e.tipo_examen,
e.resultado,
mp.nombre_comercial,
mp.dosis,
mp.frecuencia
FROM Consulta c
JOIN Paciente p ON c.id_paciente = p.id_paciente
JOIN Usuario u ON p.id_usuario = u.id_usuario
LEFT JOIN Diagnostico d ON c.id_consulta = d.id_consulta
LEFT JOIN Examen e ON c.id_consulta = e.id_consulta
LEFT JOIN MedicamentoPrescrito mp ON c.id_consulta = mp.id_consulta
WHERE u.documento = '10023456'   
ORDER BY c.fecha_consulta DESC;

-- 2. Número de pacientes por eps 
SELECT 
e.nombre_eps,
COUNT(p.id_paciente) AS total_pacientes
FROM EPS e
JOIN Paciente p ON e.id_eps = p.id_eps
GROUP BY e.nombre_eps
HAVING COUNT(p.id_paciente) = (
    SELECT MAX(total)
    FROM (
        SELECT COUNT(*) AS total
        FROM Paciente
        GROUP BY id_eps
    ) sub
);

-- 3. La enfermedad más frecuente por cada EPS
SELECT *
FROM (
    SELECT 
        e.nombre_eps,
        d.codigo_cie10,
        d.descripcion,
        COUNT(*) AS total_casos,
        ROW_NUMBER() OVER (
            PARTITION BY e.id_eps 
            ORDER BY COUNT(*) DESC
        ) AS fila
    FROM EPS e
    JOIN Paciente p ON e.id_eps = p.id_eps
    JOIN Consulta c ON p.id_paciente = c.id_paciente
    JOIN Diagnostico d ON c.id_consulta = d.id_consulta
    GROUP BY e.id_eps, e.nombre_eps, d.codigo_cie10, d.descripcion
) 
WHERE fila = 1;