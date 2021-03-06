/* Subconsulta que extrae los churners de ordenes de servicio*/
WITH
CHURNERSSO AS
(SELECT DISTINCT RIGHT(CONCAT('0000000000',NOMBRE_CONTRATO) ,10) AS CONTRATOSO, FECHA_APERTURA
 FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_ORDENES_SERVICIO_2021-01_A_2021-11_D`
 WHERE
  TIPO_ORDEN = "DESINSTALACION" 
  AND (ESTADO <> "CANCELADA" OR ESTADO <> "ANULADA")
 AND FECHA_APERTURA IS NOT NULL
 ),
  CHURNERS AS(
  SELECT
  DISTINCT CONTRATOSO,FECHA_APERTURA
  FROM CHURNERSSO t
  INNER JOIN `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-02-15_ChurnersDefinitivos_D` c
  ON t.contratoso = c.FORMATOCONTRATOCRM AND c.Maxfecha >= t.FECHA_APERTURA AND date_diff(c.Maxfecha, t.FECHA_APERTURA, MONTH) <= 3
  ),

/* Subconsulta que saca la fecha de partida para realizar el conteo de llamadas por contrato*/
FECHAFINAL AS(
  SELECT DISTINCT RIGHT(CONCAT('0000000000',CONTRATO),0) AS CONTRATO, FECHA_APERTURA
  FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_TIQUETES_SERVICIO_2021-01_A_2021-11_D`
WHERE
  CLASE IS NOT NULL AND MOTIVO IS NOT NULL AND CONTRATO IS NOT NULL AND ESTADO <> "ANULADA"  
  AND SUBAREA <> "0 A 30 DIAS"  AND SUBAREA <> "30 A 60 DIAS" AND SUBAREA <> "60 A 90 DIAS" AND SUBAREA <> "90 A 120 DIAS" AND SUBAREA <> "120 A 150 DIAS" AND SUBAREA <> "150 A 180 DIAS" AND SUBAREA <> "MAS DE 180"
AND MOTIVO <> "LLAMADA  CONSULTA DESINSTALACION"
GROUP BY CONTRATO, FECHA_APERTURA),

/* Subconsulta que saca el número de llamadas por contrato único*/
  TIQUETESPORFECHA AS (
  SELECT DISTINCT RIGHT(CONCAT('0000000000',CONTRATO),10) AS CONTRATO,FECHA_APERTURA,FECHA_FINALIZACION,COUNT(*) AS NumTiquetes
  FROM `gcp-bia-tmps-vtr-dev-01.gcp_temp_cr_dev_01.2022-01-12_CR_TIQUETES_SERVICIO_2021-01_A_2021-11_D`
  WHERE
    CLASE IS NOT NULL AND MOTIVO IS NOT NULL AND CONTRATO IS NOT NULL AND ESTADO <> "ANULADA"  
    AND SUBAREA <> "0 A 30 DIAS"  AND SUBAREA <> "30 A 60 DIAS" AND SUBAREA <> "60 A 90 DIAS" AND SUBAREA <> "90 A 120 DIAS" AND SUBAREA <> "120 A 150 DIAS" AND SUBAREA <> "150 A 180 DIAS" AND SUBAREA <> "MAS DE 180"
AND MOTIVO <> "LLAMADA  CONSULTA DESINSTALACION"
  GROUP BY CONTRATO,FECHA_APERTURA,FECHA_FINALIZACION),

/*Join para sacar el número de llamadas en 2 meses de los contratos únicos*/
TIQUETES2MESESPORCONTRATO AS(
    SELECT DISTINCT f.CONTRATO, EXTRACT (MONTH FROM f.FECHA_APERTURA) AS MES, SUM (NumTiquetes) AS NUMTIQUETES
    FROM FECHAFINAL f INNER JOIN TIQUETESPORFECHA t ON f.CONTRATO = t.CONTRATO
    WHERE (f.FECHA_APERTURA > t.fecha_apertura AND DATE_DIFF(f.FECHA_APERTURA, t.FECHA_APERTURA, DAY) <= 60) or f.FECHA_APERTURA = t.fecha_apertura
    GROUP BY CONTRATO, MES
),
/*Join para sacar el número de llamadas en 2 meses de los churners*/
TIQUETES2MESESCHURNERS AS(
  SELECT DISTINCT f.CONTRATO, EXTRACT (MONTH FROM f.FECHA_APERTURA) AS MES, SUM (NumTiquetes) AS NUMTIQUETESCHURNERS
    FROM FECHAFINAL f INNER JOIN TIQUETESPORFECHA t ON f.CONTRATO = t.CONTRATO INNER JOIN CHURNERS c on f.contrato = c.CONTRATOSO
    WHERE ((f.FECHA_APERTURA > t.fecha_apertura AND DATE_DIFF(f.FECHA_APERTURA, t.FECHA_APERTURA, DAY) <= 60) or f.FECHA_APERTURA = t.fecha_apertura) AND c.FECHA_APERTURA > f.FECHA_APERTURA AND DATE_DIFF(c.FECHA_APERTURA, f.FECHA_APERTURA, DAY) <= 60
    GROUP BY CONTRATO, MES
),
/*Consulta que saca los tiers de llamadas para los contratos únicos*/
TIERSTIQUETESCONTRATOS AS(
  SELECT MES,
  CASE WHEN NUMTIQUETES = 1 THEN "1"
  WHEN NUMTIQUETES=2 THEN "2"
  WHEN NUMTIQUETES=3 THEN "3"
  WHEN NUMTIQUETES=4 THEN "4"
  WHEN NUMTIQUETES>4 THEN "5+"
  END AS TIERTIQUETES, COUNT(DISTINCT CONTRATO) AS NUMCONTRATOS
  FROM TIQUETES2MESESPORCONTRATO
  GROUP BY TIERTIQUETES,MES),

/*Consulta que saca los tiers de llamadas para los churners*/
TIERSTIQUETESCHURNERS AS(
  SELECT MES,
  CASE WHEN NUMTIQUETESCHURNERS = 1 THEN "1"
  WHEN NUMTIQUETESCHURNERS=2 THEN "2"
  WHEN NUMTIQUETESCHURNERS=3 THEN "3"
  WHEN NUMTIQUETESCHURNERS=4 THEN "4"
  WHEN NUMTIQUETESCHURNERS>4 THEN "5+"
  END AS TIERTIQUETESCHURNERS, COUNT(DISTINCT CONTRATO) AS NUMCHURNERS
  FROM TIQUETES2MESESCHURNERS
  GROUP BY TIERTIQUETESCHURNERS,MES)

/* Consulta final con los Qs y el churn rate para cada tier de tiquetes de llamadas totales*/
SELECT tt.MES as Mes, tt.TIERTIQUETES AS TierTiq, NUMCONTRATOS as NumContratos, NUMCHURNERS as Churners, ROUND (NUMCHURNERS/NUMCONTRATOS,4) as ChurnRate
FROM TIERSTIQUETESCONTRATOS tt LEFT JOIN TIERSTIQUETESCHURNERS tc ON tt.MES = tc.MES AND tt.TIERTIQUETES = tc.TIERTIQUETESCHURNERS
ORDER BY Mes, TierTiq
