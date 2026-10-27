# Respuestas a las preguntas de negocio

[English](business_answers.md) | **Español**

Cada respuesta sale de una consulta en [`sql/queries/`](../sql/queries), ejecutada contra el repositorio analítico después de correr el DAG. Las tablas de abajo son el **resultado exacto de cada consulta** (mismas columnas, mismo orden, mismas filas; montos en libras esterlinas, GBP). Periodo: 01/12/2010 a 09/12/2011.

> **Formato de números.** Esta versión usa el formato que muestra DBeaver con configuración en español: `.` para miles y `,` para decimales (`1.028.320,38`). La [versión en inglés](business_answers.md) usa `1,028,320.38`. Los valores son idénticos. DBeaver oculta los ceros finales (`758.090,5`); aquí cada monto conserva los dos decimales que devuelve PostgreSQL (`758.090,50`).

**Totales del periodo** (`SUM` sobre `dwh.sales_fact` y `dwh.returns_fact`): revenue bruto **10.246.667,47**, devoluciones **475.901,16**, revenue neto **9.770.766,31**.

---

## P1. Evolución mensual de las ventas netas

Consulta: [`q1_monthly_net_sales.sql`](../sql/queries/q1_monthly_net_sales.sql)

| year_month | gross_revenue | returns_amount | net_revenue | return_pct | pct_change_vs_prev_month |
|---|---:|---:|---:|---:|---:|
| 2010-12 | 775.638,36 | 17.547,86 | 758.090,50 | 2,26 | NULL |
| 2011-01 | 670.380,24 | 91.525,05 | 578.855,19 | 13,65 | -23,64 |
| 2011-02 | 507.799,87 | 8.335,52 | 499.464,35 | 1,64 | -13,72 |
| 2011-03 | 689.833,51 | 10.504,30 | 679.329,21 | 1,52 | 36,01 |
| 2011-04 | 515.377,99 | 33.316,06 | 482.061,93 | 6,46 | -29,04 |
| 2011-05 | 739.938,15 | 8.948,23 | 730.989,92 | 1,21 | 51,64 |
| 2011-06 | 737.558,98 | 13.713,84 | 723.845,14 | 1,86 | -0,98 |
| 2011-07 | 688.219,34 | 11.407,26 | 676.812,08 | 1,66 | -6,50 |
| 2011-08 | 724.216,50 | 22.926,57 | 701.289,93 | 3,17 | 3,62 |
| 2011-09 | 1.028.320,38 | 16.980,64 | 1.011.339,74 | 1,65 | 44,21 |
| 2011-10 | 1.103.314,25 | 41.613,03 | 1.061.701,22 | 3,77 | 4,98 |
| 2011-11 | 1.451.578,98 | 24.991,44 | 1.426.587,54 | 1,72 | 34,37 |
| 2011-12 | 614.490,92 | 174.091,36 | 440.399,56 | 28,33 | -69,13 |

2011-12 solo tiene datos hasta el 9 de diciembre.

**Respuesta.** Entre enero y agosto de 2011 las ventas netas se mueven entre **482.061,93** (abril) y **730.989,92** (mayo) al mes. Desde septiembre crecen fuerte: **noviembre de 2011 es el pico con 1.426.587,54**, casi el triple de febrero (499.464,35). Septiembre a noviembre suman 3.583.213,61 de revenue bruto, el **34,97 %** de todo el periodo.

**Implicación.** El negocio es estacional (temporada navideña). Los picos de devolución de enero (13,65 %) y diciembre de 2011 (28,33 %) no son estacionales: cada uno viene de un solo pedido cancelado (ver P7).

---

## P2. Categorías por revenue bruto y proporción de devoluciones

Consulta: [`q2_category_revenue_returns.sql`](../sql/queries/q2_category_revenue_returns.sql)

| category | products | gross_revenue | pct_of_total_gross | returns_amount | return_pct_amount | return_pct_units |
|---|---:|---:|---:|---:|---:|---:|
| Home | 1.904 | 6.126.782,80 | 59,79 | 239.573,39 | 3,91 | 8,04 |
| Clothing | 535 | 1.204.941,48 | 11,76 | 20.372,00 | 1,69 | 3,89 |
| Stationery | 546 | 1.143.067,52 | 11,16 | 184.719,19 | 16,16 | 13,70 |
| Uncategorized | 680 | 867.373,95 | 8,46 | 13.421,71 | 1,55 | 9,54 |
| Electronics | 135 | 474.246,21 | 4,63 | 9.908,01 | 2,09 | 5,25 |
| Sports | 127 | 430.255,51 | 4,20 | 7.906,86 | 1,84 | 3,84 |

`return_pct_amount` = devoluciones / revenue bruto. `return_pct_units` = unidades devueltas / unidades vendidas.

**Respuesta.** **Home** genera más revenue bruto: **6.126.782,80 (59,79 %)**, casi 6 de cada 10 libras. **Stationery** tiene la mayor proporción de devoluciones: **16,16 %** del monto (13,70 % de las unidades), seguida de Home (3,91 %).

**Implicación.** El 16,16 % de Stationery no es un problema de la categoría: el producto 23843 devolvió por sí solo 168.469,60 (un solo pedido cancelado, ver P7). Sin él, la tasa de la categoría baja a (184.719,19 − 168.469,60) / (1.143.067,52 − 168.469,60) = **1,67 %**, en línea con el resto.

---

## P3. Top 10 de productos por revenue neto y top 10 por tasa de devolución

Consulta: [`q3_top_products.sql`](../sql/queries/q3_top_products.sql)

**P3a. Top 10 por revenue neto**

| stock_code | product_description | category | gross_revenue | returns_amount | net_revenue |
|---|---|---|---:|---:|---:|
| 22423 | REGENCY CAKESTAND 3 TIER | Home | 174.156,54 | 9.697,05 | 164.459,49 |
| 85123A | WHITE HANGING HEART T-LIGHT HOLDER | Home | 106.415,23 | 6.624,30 | 99.790,93 |
| 47566 | PARTY BUNTING | Home | 99.445,23 | 1.201,35 | 98.243,88 |
| 85099B | JUMBO BAG RED RETROSPOT | Clothing | 94.159,81 | 1.984,02 | 92.175,79 |
| 23084 | RABBIT NIGHT LIGHT | Electronics | 66.870,03 | 208,40 | 66.661,63 |
| 22086 | PAPER CHAIN KIT 50'S CHRISTMAS | Stationery | 64.875,59 | 1.160,35 | 63.715,24 |
| 84879 | ASSORTED COLOUR BIRD ORNAMENT | Home | 58.927,62 | 135,20 | 58.792,42 |
| 79321 | CHILLI LIGHTS | Electronics | 54.096,36 | 349,70 | 53.746,66 |
| 22502 | PICNIC BASKET WICKER SMALL | Sports | 51.408,77 | 385,25 | 51.023,52 |
| 22197 | POPCORN HOLDER | Home | 51.334,47 | 366,55 | 50.967,92 |

**P3b. Top 10 por tasa de devolución** (solo productos con al menos 1.000 GBP de revenue bruto)

| stock_code | product_description | category | units_sold | units_returned | gross_revenue | returns_amount | return_pct |
|---|---|---|---:|---:|---:|---:|---:|
| 23843 | PAPER CRAFT , LITTLE BIRDIE | Stationery | 80.995 | 80.995 | 168.469,60 | 168.469,60 | 100,00 |
| 23166 | MEDIUM CERAMIC TOP STORAGE JAR | Home | 78.033 | 74.494 | 81.700,92 | 77.479,64 | 94,83 |
| 85232B | SET OF 3 BABUSHKA STACKING TINS | Home | 274 | 256 | 1.356,30 | 1.258,05 | 92,76 |
| 23113 | PANTRY CHOPPING BOARD | Home | 1.154 | 2.386 | 5.868,50 | 4.803,06 | 81,84 |
| 23056 | FLOWERS CHANDELIER T-LIGHT HOLDER | Home | 963 | 789 | 2.898,12 | 1.859,07 | 64,15 |
| 23055 | IVORY CHANDELIER T-LIGHT HOLDER | Home | 657 | 830 | 1.395,18 | 690,72 | 49,51 |
| 22313 | OFFICE MUG WARMER PINK | Home | 565 | 250 | 1.564,83 | 637,50 | 40,74 |
| 23064 | CINDERELLA CHANDELIER | Home | 221 | 79 | 3.717,56 | 1.514,05 | 40,73 |
| 22920 | HERB MARKER BASIL | Home | 3.423 | 1.527 | 2.153,34 | 841,05 | 39,06 |
| 21108 | FAIRY CAKE FLANNEL ASSORTED COLOUR | Home | 10.241 | 3.150 | 18.056,28 | 6.591,42 | 36,50 |

**Respuesta.** El mejor producto por revenue neto es **22423 REGENCY CAKESTAND 3 TIER (164.459,49)**, seguido de 85123A WHITE HANGING HEART T-LIGHT HOLDER (99.790,93) y 47566 PARTY BUNTING (98.243,88). La tasa de devolución más alta es de **23843 PAPER CRAFT , LITTLE BIRDIE (100,00 %)** y **23166 MEDIUM CERAMIC TOP STORAGE JAR (94,83 %)**.

**Implicación.** El mínimo de 1.000 GBP evita que un producto con una sola venta devuelta aparezca con 100 %. Los tres productos "CHANDELIER" (23056, 23055, 23064) aparecen juntos: es una línea de producto con problemas, no un caso aislado. Las unidades devueltas pueden superar a las vendidas (23113, 23055) porque algunas devoluciones o ajustes de inventario corresponden a ventas fuera del periodo.

---

## P4. Países por número de transacciones y ticket promedio

Consulta: [`q4_country_avg_ticket.sql`](../sql/queries/q4_country_avg_ticket.sql). Transacción = factura de venta (`invoice_no`); ticket = revenue bruto / facturas; `customers` excluye al cliente anónimo.

| country_name | invoices | pct_invoices | gross_revenue | avg_ticket | customers |
|---|---:|---:|---:|---:|---:|
| United Kingdom | 17.901 | 90,53 | 8.723.891,82 | 487,34 | 3.916 |
| Germany | 443 | 2,24 | 205.381,15 | 463,61 | 94 |
| France | 382 | 1,93 | 184.493,00 | 482,97 | 87 |
| Ireland | 282 | 1,43 | 270.850,86 | 960,46 | 3 |
| Belgium | 98 | 0,50 | 36.927,34 | 376,81 | 25 |
| Netherlands | 93 | 0,47 | 283.889,34 | 3.052,57 | 9 |
| Spain | 88 | 0,45 | 55.706,56 | 633,03 | 30 |
| Australia | 56 | 0,28 | 138.103,81 | 2.466,14 | 9 |
| Portugal | 50 | 0,25 | 26.951,11 | 539,02 | 19 |
| Switzerland | 50 | 0,25 | 53.065,60 | 1.061,31 | 21 |
| Finland | 40 | 0,20 | 18.344,88 | 458,62 | 12 |
| Italy | 35 | 0,18 | 15.820,24 | 452,01 | 14 |
| Sweden | 34 | 0,17 | 36.828,83 | 1.083,20 | 8 |
| Norway | 32 | 0,16 | 32.454,64 | 1.014,21 | 10 |
| Channel Islands | 25 | 0,13 | 19.997,54 | 799,90 | 9 |
| Japan | 19 | 0,10 | 37.416,37 | 1.969,28 | 8 |
| Poland | 19 | 0,10 | 6.974,65 | 367,09 | 6 |
| Denmark | 18 | 0,09 | 18.211,34 | 1.011,74 | 9 |
| Austria | 17 | 0,09 | 8.742,68 | 514,28 | 11 |
| Cyprus | 14 | 0,07 | 13.167,16 | 940,51 | 8 |
| Unknown | 13 | 0,07 | 4.740,94 | 364,69 | 4 |
| Israel | 8 | 0,04 | 8.129,41 | 1.016,18 | 3 |
| Hong Kong | 7 | 0,04 | 9.744,19 | 1.392,03 | 0 |
| Iceland | 7 | 0,04 | 4.310,00 | 615,71 | 1 |
| United States | 5 | 0,03 | 3.580,39 | 716,08 | 4 |
| Malta | 5 | 0,03 | 2.070,59 | 414,12 | 2 |
| Canada | 5 | 0,03 | 3.115,44 | 623,09 | 4 |
| Greece | 5 | 0,03 | 4.425,52 | 885,10 | 4 |
| Lithuania | 4 | 0,02 | 1.661,06 | 415,27 | 1 |
| Singapore | 4 | 0,02 | 9.120,39 | 2.280,10 | 1 |
| European Community | 3 | 0,02 | 1.159,25 | 386,42 | 1 |
| Bahrain | 3 | 0,02 | 754,14 | 251,38 | 2 |
| United Arab Emirates | 2 | 0,01 | 1.864,78 | 932,39 | 2 |
| Czech Republic | 2 | 0,01 | 786,74 | 393,37 | 1 |
| South Africa | 1 | 0,01 | 1.002,31 | 1.002,31 | 1 |
| Lebanon | 1 | 0,01 | 1.693,88 | 1.693,88 | 1 |
| Saudi Arabia | 1 | 0,01 | 145,92 | 145,92 | 1 |
| Brazil | 1 | 0,01 | 1.143,60 | 1.143,60 | 1 |

**Respuesta.** El **Reino Unido** tiene **17.901 facturas (90,53 %)**. Alemania (2,24 %), Francia (1,93 %) e Irlanda (1,43 %) suman otro 5,60 %. El ticket varía mucho: Reino Unido, Alemania y Francia están entre **463,61 y 487,34**, mientras que **Países Bajos (3.052,57)** y **Australia (2.466,14)** tienen tickets 5 a 6 veces mayores con solo 9 clientes cada uno.

**Implicación.** Los mercados internacionales con ticket alto son de mayoristas: pocos clientes, compras grandes. Perder uno de esos clientes pesa mucho en el país.

---

## P5. Clientes identificados vs. transacciones sin CustomerID

Consulta: [`q5_identified_vs_anonymous.sql`](../sql/queries/q5_identified_vs_anonymous.sql)

| customer_type | invoices | pct_of_gross | gross_revenue | avg_ticket | products_per_invoice | units_per_line | avg_unit_price | return_pct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Identified | 18.402 | 85,26 | 8.736.675,79 | 474,77 | 21,3 | 13,1 | 2,87 | 5,40 |
| No CustomerID | 1.371 | 14,74 | 1.509.991,68 | 1.101,38 | 95,8 | 3,2 | 4,46 | 0,27 |

**Respuesta.** Sí, se comportan distinto. Las facturas sin cliente son pocas (**1.371**) pero muy largas: **95,8 productos por factura** contra 21,3, con pocas unidades por línea (3,2 contra 13,1) y precio unitario más alto (4,46 contra 2,87). Su ticket es **1.101,38**, más del doble del identificado (474,77), y casi no tienen devoluciones (**0,27 %** contra 5,40 %). El patrón parece de ventas al detal (mostrador o pedidos sin registro), no de mayoristas.

**Implicación.** Excluir estas transacciones habría borrado el **14,74 %** del revenue bruto (1.509.991,68). Conviene que DataMart capture el cliente también en ese canal.

---

## P6. Productos sin descripción consistente y total de códigos únicos

Consulta: [`q6_inconsistent_descriptions.sql`](../sql/queries/q6_inconsistent_descriptions.sql)

**P6b. Totales**

| unique_product_codes | with_inconsistent_description | pct_inconsistent | without_description |
|---:|---:|---:|---:|
| 3.927 | 637 | 16,22 | 97 |

**P6a. Códigos con más de una descripción** (la consulta devuelve 637 filas; aquí están las que tienen 4 variantes o más)

| stock_code | canonical_name | description_variants | category |
|---|---|---:|---|
| 20713 | JUMBO BAG OWLS | 8 | Clothing |
| 23084 | RABBIT NIGHT LIGHT | 7 | Electronics |
| 21830 | ASSORTED CREEPY CRAWLIES | 6 | Sports |
| 85175 | CACTI T-LIGHT CANDLES | 6 | Home |
| 21181 | PLEASE ONE PERSON METAL SIGN | 5 | Home |
| 23131 | MISTLETOE HEART WREATH CREAM | 5 | Home |
| 23343 | JUMBO BAG VINTAGE CHRISTMAS | 5 | Clothing |
| 72807A | SET/3 ROSE CANDLE IN JEWELLED BOX | 5 | Home |
| 85172 | HYACINTH BULB T-LIGHT CANDLES | 5 | Home |
| 21621 | VINTAGE UNION JACK BUNTING | 4 | Home |
| 21823 | PAINTED METAL HEART WITH HOLLY BELL | 4 | Home |
| 21829 | DINOSAUR KEYRINGS ASSORTED | 4 | Clothing |
| 22121 | NOEL WOODEN BLOCK LETTERS | 4 | Sports |
| 22501 | PICNIC BASKET WICKER LARGE | 4 | Sports |
| 22719 | GUMBALL MONOCHROME COAT RACK | 4 | Home |
| 22734 | SET OF 6 RIBBONS VINTAGE CHRISTMAS | 4 | Home |
| 22812 | PACK 3 BOXES CHRISTMAS PANNETONE | 4 | Home |
| 22837 | HOT WATER BOTTLE BABUSHKA | 4 | Home |
| 22927 | GREEN GIANT GARDEN THERMOMETER | 4 | Home |
| 23118 | PARISIENNE JEWELLERY DRAWER | 4 | Home |
| 23196 | VINTAGE LEAF MAGNETIC NOTEPAD | 4 | Stationery |
| 23203 | JUMBO BAG VINTAGE DOILY | 4 | Clothing |
| 23209 | LUNCH BAG VINTAGE DOILY | 4 | Clothing |
| 23236 | STORAGE TIN VINTAGE DOILY | 4 | Home |
| 35965 | FOLKART HEART NAPKIN RINGS | 4 | Home |
| 37327 | ASSTD MULTICOLOUR CIRCLES MUG | 4 | Home |
| 46000S | POLYESTER FILLER PAD 40X40CM | 4 | Home |
| 72802A | ROSE SCENT CANDLE IN JEWELLED BOX | 4 | Home |
| 72807B | SET/3 OCEAN SCENT CANDLE JEWEL BOX | 4 | Home |
| 72807C | SET/3 VANILLA SCENTED CANDLE IN BOX | 4 | Home |
| 79030G | TUMBLER NEW ENGLAND | 4 | Home |
| 82583 | HOT BATHS METAL SIGN | 4 | Home |
| 82600 | NO SINGING METAL SIGN | 4 | Home |
| 85123A | WHITE HANGING HEART T-LIGHT HOLDER | 4 | Home |
| 85185B | PINK HORSE SOCK PUPPET | 4 | Uncategorized |

**P6c. Códigos de la fuente diaria que no son productos del catálogo** (rechazados como `not_a_product_code`)

| code | lines |
|---|---:|
| POST | 1.256 |
| DOT | 710 |
| M | 572 |
| C2 | 144 |
| D | 77 |
| S | 63 |
| BANKCHARGES | 37 |
| AMAZONFEE | 34 |
| CRUK | 16 |
| GIFT_0001_20 | 10 |
| GIFT_0001_10 | 9 |
| GIFT_0001_30 | 8 |
| GIFT_0001_50 | 4 |
| PADS | 4 |
| B | 3 |
| GIFT_0001_40 | 3 |

**Respuesta.** El DWH tiene **3.927 códigos de producto únicos**; **637 (16,22 %)** llegan con más de una descripción y 97 nunca traen descripción. Los casos más extremos son 20713 JUMBO BAG OWLS (8 variantes), 23084 RABBIT NIGHT LIGHT (7), 21830 ASSORTED CREEPY CRAWLIES y 85175 CACTI T-LIGHT CANDLES (6). Además, 16 códigos de la fuente no son productos (2.950 líneas: POST, DOT, M, C2...) y quedan fuera de la dimensión de productos.

**Implicación.** Uno de cada seis productos tiene la descripción inconsistente: el sistema operacional permite texto libre en un campo que debería venir del catálogo. Las variantes suelen ser notas de ajuste escritas a mano (`damaged`, `check`, `?`) o cambios de nombre del catálogo.

---

## P7. Recomendación al equipo de producto

Consulta: [`q7_product_recommendation.sql`](../sql/queries/q7_product_recommendation.sql). Productos con al menos 5.000 GBP de revenue bruto, ordenados por monto devuelto.

| stock_code | product_description | category | gross_revenue | returns_amount | net_revenue | return_pct | pct_of_all_returns |
|---|---|---|---:|---:|---:|---:|---:|
| 23843 | PAPER CRAFT , LITTLE BIRDIE | Stationery | 168.469,60 | 168.469,60 | 0,00 | 100,00 | 41,14 |
| 23166 | MEDIUM CERAMIC TOP STORAGE JAR | Home | 81.700,92 | 77.479,64 | 4.221,28 | 94,83 | 18,92 |
| 22423 | REGENCY CAKESTAND 3 TIER | Home | 174.156,54 | 9.697,05 | 164.459,49 | 5,57 | 2,37 |
| 85123A | WHITE HANGING HEART T-LIGHT HOLDER | Home | 106.415,23 | 6.624,30 | 99.790,93 | 6,22 | 1,62 |
| 21108 | FAIRY CAKE FLANNEL ASSORTED COLOUR | Home | 18.056,28 | 6.591,42 | 11.464,86 | 36,50 | 1,61 |
| 23113 | PANTRY CHOPPING BOARD | Home | 5.868,50 | 4.803,06 | 1.065,44 | 81,84 | 1,17 |
| 48185 | DOORMAT FAIRY CAKE | Home | 23.872,91 | 4.554,90 | 19.318,01 | 19,08 | 1,11 |
| 21175 | GIN + TONIC DIET METAL SIGN | Home | 27.029,97 | 3.775,33 | 23.254,64 | 13,97 | 0,92 |
| 47566B | TEA TIME PARTY BUNTING | Home | 12.926,42 | 3.692,95 | 9.233,47 | 28,57 | 0,90 |
| 22273 | FELTCRAFT DOLL MOLLY | Sports | 12.001,59 | 3.512,65 | 8.488,94 | 29,27 | 0,86 |
| 71477 | COLOUR GLASS. STAR T-LIGHT HOLDER | Home | 20.650,66 | 3.443,62 | 17.207,04 | 16,68 | 0,84 |
| 22191 | IVORY DINER WALL CLOCK | Electronics | 11.911,65 | 2.653,70 | 9.257,95 | 22,28 | 0,65 |
| 21843 | RED RETROSPOT CAKE STAND | Home | 21.354,30 | 2.480,50 | 18.873,80 | 11,62 | 0,61 |
| 85099B | JUMBO BAG RED RETROSPOT | Clothing | 94.159,81 | 1.984,02 | 92.175,79 | 2,11 | 0,48 |
| 22655 | VINTAGE RED KITCHEN CABINET | Home | 8.125,00 | 1.730,50 | 6.394,50 | 21,30 | 0,42 |

> `pct_of_all_returns` se calcula después del filtro `WHERE gross_revenue >= 5000`, así que su denominador son las devoluciones de los productos de ese filtro (409.461,67), no el total de devoluciones del periodo (475.901,16).

**Hallazgo.** Dos pedidos explican más de la mitad de todas las devoluciones del periodo. Cada uno se vendió y se canceló el mismo día:

| stock_code | Pedido (venta / cancelación) | Fecha (UTC) | Unidades | Monto |
|---|---|---|---:|---:|
| 23843 | 581483 / C581484 | 2011-12-09 | 80.995 | 168.469,60 |
| 23166 | 541431 / C541433 | 2011-01-18 | 74.215 | 77.183,60 |

Los productos 23843 y 23166 devolvieron **245.949,24** en total, el **51,68 % de todas las devoluciones** (475.901,16), y son la causa de los picos de enero (13,65 %) y diciembre (28,33 %) de la P1.

**Recomendación.** Poner un **control de cantidad máxima por línea de pedido** (por ejemplo, confirmación obligatoria por encima de 10.000 unidades, cuando una línea de venta típica tiene 13,1 unidades, ver P5). Sin esos dos pedidos la tasa de devolución del periodo pasaría de **4,64 % a 2,30 %**, y el revenue bruto dejaría de inflarse con pedidos que se cancelan el mismo día.

**Segunda prioridad.** Revisar la línea **"fairy cake"** de Home: 21108 FAIRY CAKE FLANNEL ASSORTED COLOUR (36,50 % devuelto sobre 18.056,28) y 48185 DOORMAT FAIRY CAKE (19,08 % sobre 23.872,91) devuelven juntos 11.146,32. Igual con las lámparas **"CHANDELIER"** (23056, 23055, 23064 en la P3b, todas por encima del 40 %). Antes de la temporada septiembre-noviembre, que concentra el 34,97 % de las ventas, conviene revisar la calidad, la foto y la descripción de estos productos.
