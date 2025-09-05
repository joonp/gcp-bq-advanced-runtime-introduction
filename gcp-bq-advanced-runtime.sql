## SQL 2문장으로 빅쿼리 성능 떡상시키는 꿀팁(feat. advanced runtime)
## https://github.com/joonp/gcp-bq-advanced-runtime-introduction

 
## 수행하려는 쿼리의 대상 데이터셋의 리전으로 변경: `[dataset-region].query_runtime`
## 튜토리얼에서는 빅쿼리 공개 데이터셋으로 진행 `region-us`
ALTER PROJECT `[your-project-id]`
SET OPTIONS (  
    `region-us.query_runtime` = 'advanced'
);

## 인포메이션 스키마를 통하여 활성화 상태 확인 가능(상태 변경후 인포메이션 스키마 반영까지는 최대 15초 소요)
## 쿼리 결과(results)에서 option_name(query_runtime), option_value(ADVANCED) 로 나오면 활성화(enable)된 상태
SELECT option_name, option_value
FROM `region-us`.INFORMATION_SCHEMA.PROJECT_OPTIONS;


## 빅쿼리 공개 데이터셋에 존재하는 샘플 테이블에서 테스트 쿼리 수행
## 테스트 수행시에는 결과 비교를 위하여 반드시 Query Settings 에서 Use cached results를 체크 해제하여 주시기 바랍니다.
SELECT
 	p.category,
 	dc.name AS distribution_center_name,
 	u.country AS user_country,
 	SUM(oi.sale_price) AS total_sales_amount,
 	COUNT(DISTINCT o.order_id) AS total_unique_orders,
 	COUNT(DISTINCT o.user_id) AS total_unique_customers_who_ordered,
 	AVG(oi.sale_price) AS average_item_sale_price,
 	SUM(CASE WHEN oi.status = 'Complete' THEN 1 ELSE 0 END) AS completed_order_items_count,
 	COUNT(DISTINCT p.id) AS total_unique_products_sold,
 	COUNT(DISTINCT ii.id) AS total_unique_inventory_items_sold
 FROM
 	`bigquery-public-data.thelook_ecommerce.orders` AS o,
 	`bigquery-public-data.thelook_ecommerce.order_items` AS oi,
 	`bigquery-public-data.thelook_ecommerce.products` AS p,
 	`bigquery-public-data.thelook_ecommerce.inventory_items` AS ii,
 	`bigquery-public-data.thelook_ecommerce.distribution_centers` AS dc,
 	`bigquery-public-data.thelook_ecommerce.users` AS u
 WHERE
 	o.order_id = oi.order_id AND oi.product_id = p.id AND ii.product_distribution_center_id = dc.id AND oi.inventory_item_id = ii.id AND o.user_id = u.id
 GROUP BY
 	p.category,
 	dc.name,
 	u.country
 ORDER BY
 	total_sales_amount DESC
 LIMIT 1000;


## BigQuery Advanced Runtime 기능 비활성화
## 수행하려는 쿼리의 대상 데이터셋의 리전으로 변경: `[dataset-region].query_runtime`
## 튜토리얼에서는 빅쿼리 공개 데이터셋으로 진행 `region-us`
ALTER PROJECT `[your-project-id]`
SET OPTIONS (  
    `region-us.query_runtime` = null
);

## BigQuery Advanced Runtime 기능 비활성화 상태 확인
## 인포메이션 스키마를 통하여 활성화 상태 확인 가능, 상태 변경후 인포메이션 스키마 반영까지는 최대 15초 소요
## 쿼리 결과(Results)내역에 There is no data to display. 로 나오면 비활성화(disable) 상태
SELECT option_name, option_value
FROM `region-us`.INFORMATION_SCHEMA.PROJECT_OPTIONS;


