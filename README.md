# SQL 2문장으로 빅쿼리 성능 떡상시키는 꿀팁(feat. advanced runtime)

## Intro(시작하며...)
구글 클라우드 [빅쿼리(BigQuery)](https://cloud.google.com/bigquery/docs/introduction)는 1998년 구글 설립 이후로 구글 내부에서 연구개발된 모든 기술이 집약되어 있는 매우 고도화된 프로덕트라고 말할 수가 있습니다. 빅쿼리는 아래의 기술을 사용하여 스토리지와 컴퓨팅 노드를 완전히 분리하고, 각각을 독립적으로 확장할수 아키텍처를 갖고 있는 **페타바이트 스케일 서버리스 데이터웨어하우스(Petabyte Scale Serverless Data Warehouse)** 입니다.

-   **[Dremel(분산 SQL 실행 엔진)](https://research.google/pubs/dremel-interactive-analysis-of-web-scale-datasets-2/)**: SQL 쿼리를 실행 트리로 변환하여 수만대의 컴퓨팅 노드에서 분산처리
- **[Colossus(분산 스토리지 시스템)](https://cloud.google.com/blog/products/storage-data-transfer/a-peek-behind-colossus-googles-file-system)**: 데이터를 안정적으로 복제 및 관리 가능한 페타바이트급 스토리지, 빅쿼리는 데이터를 Colossus 환경에 컬럼 기반형태로 저장([Columnar Storage](https://cloud.google.com/bigquery/docs/storage_overview))하여 효율성과 스캔 성능을 극대화
-   **[Borg(클러스터 관리 시스템)](https://research.google/pubs/large-scale-cluster-management-at-google-with-borg/)**: 쿠버네티스(k8s)의 모태(母胎)로 수만대의 클러스터 컴퓨팅 자원을 할당하고 관리하는 시스템, 쿼리 실행에 필요한 자원(CPU, 메모리 등)을 필요한 순간에 필요한 만큼 할당
- **[Jupiter(초고속 소프트웨어 정의 네트워킹)](https://research.google/pubs/jupiter-evolving-transforming-googles-datacenter-network-via-optical-circuit-switches-and-software-defined-networking/)**: [13.1페타비트/초(Petabit/sec)의 대역폭을 제공하는 기술](https://cloud.google.com/blog/products/networking/speed-scale-reliability-25-years-of-data-center-networking)로써, Dremel 엔진의 각노드(slots)간 데이터 셔플링(shuffling)과 같은 대용량 데이터 처리시 네트워크 병목현상 최소화

  <p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/445461e6-3081-4b9d-ba48-3983c7d88739">    

이번에 소개할 **Advanced Runtime은 빅쿼리의 쿼리 처리 성능과 효율성을 향상시키는 기능의 집합체**입니다. 특히 사용자가 기존 데이터에 대한 스키마나 쿼리를 변경할 필요가 전혀 없으며, 빅쿼리가 자동으로 적격한 쿼리에 적용하여서 성능을 가속화 할수가 있습니다. 해당 기능은 크게 [Enhanced Vectorization](https://cloud.google.com/blog/products/data-analytics/understanding-bigquery-enhanced-vectorization), [Short Query Optimization](https://cloud.google.com/blog/products/data-analytics/short-query-optimizations-in-bigquery-advanced-runtime) 으로 나누어 집니다.

-  **Enhanced Vectorization** : 벡터화된 런타임을 통하여 조인(Join)과 어그리게이션(Aggregation) 최적화
-  **Short Query Optimization**: 셔플 및 분산 처리에 대한 오버헤드를 줄여서 숏쿼리(Short Query) 최적화

## 1.  Enhanced Vectorization: 벡터화를 통한 차세대 쿼리 실행 기술
    
벡터화(Vectorization)는 과거의 CPU가 한번에 하나의 데이터만 처리하는 [스칼라(Scalar)](https://ko.wikipedia.org/wiki/%EC%8A%A4%EC%B9%BC%EB%9D%BC_%ED%94%84%EB%A1%9C%EC%84%B8%EC%84%9C) 방식이 아닌, [SIMD(Single Instruction Multiple Data](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data)) 기술을 통하여 한번의 명령어로 여러 데이터를 동시에 처리할 수 있는 방식을 말합니다.

스칼라 방식은 쿼리를 처리할때 행단위(`row-by-row`)방식은 쿼리 엔진이 하나의 행(`row`)을 읽고, 해당 행(`row`)의 연산을 마친후 다음 행(row)으로 넘어가는 구조로서, 데이터의 양이 많아질수록 효율이 매우 떨어집니다.

<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/06437795-e334-44ef-b2c4-70f908a57237">    

반면, **벡터화는 여러 행의 데이터를 묶어서 벡터(Vector)형태로 처리하는 방식**입니다. 한번에 묶인 벡터 데이터에 대하여 쿼리 엔진에서 연산을 수행하므로, 빅쿼리의 벡터화된 쿼리 실행(Vectorized a query execution)은 CPU 캐시 크기의 블록 단위로 컬럼형 데이터를 한번에 처리[SIMD(Single Instruction Multiple Data](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data))하여 효율을 높이는 방식입니다.

여기서 추가로, 데이터 인코딩 최적화(Data-encoding-enabled optimizations), 표현식 폴딩(Expression Folding), 공통 하위 표현식 제거(Common Subexpression Elimination), 병렬화 가능한 조인 및 집계 알고리즘(Parallelizable join and aggregation algorithms) 등과 같은 기술을 추가하여 쿼리처리에 벡터화(Vectorization)를 적용하였습니다.

-  **인코딩된 데이터에 대한 직접 처리**: 백만개의 행에 단 3개의 고유 값(`sedan, wagon, suv`)만 존재하는 컬럼이 있다면, 딕셔너리 인코딩을 통하여 3개값만 저장하고, 각 행에는 작은 정수 ID(0, 1, 2)만 할당하여 데이터 저장 용량 절감 효과를 제공합니다. 또한, 향상된 벡터화(Enhanced Vectorization)는 해당 **인코딩된 데이터를 풀지(디코딩) 않고 직접 처리하여 중복 계산을 원천적으로 제거하고, 쿼리 처리에 필요한 데이터 용량이 줄기 때문에 쿼리 성능을 극적으로 향상** 시킬수가 있습니다.

<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/d8763f73-9a6e-4e6f-8128-dbcc8a87e6db">    

- **표현식 폴딩(Expression Folding)**: 표현식 폴딩은 쿼리 실행 시점에 계산할 필요 없이, 계획(plan) 단계에서 그 결과를 미리 계산할 수 있는 표현식을 상수값으로 대체하는 기법입니다. 빅쿼리는 계획단계에서 쿼리를 분석하여 결과가 항상 동일한 표현식을 찾아내고 이를 상수값으로 접어서(fold) 쿼리 자체를 단순화 합니다. 아래 쿼리에서 `sales_price` 에 `1.1`을 곱하고, 그 결과에 다시 `1.05`를 곱하는 두번의 연산이 있다면, 표현식 폴딩을 적용하여 `1.1 * 1.05` 를 미리 계산하여 `1.155` 라는 상수를 미리 얻어서, 향후 `sales_price * 1.55` 단일 연산으로 쿼리를 실행합니다. 이처럼 표현식 폴딩은 **쿼리 계획 단계에서 상수를 미리 계산하여 실행 시점에 필요한 연산의 양을 줄여 쿼리의 실행 속도를 향상시키고, 빅쿼리 슬롯 자원을 효율적으로 사용** 하게 됩니다.

    ```sql
    ## Expression Folding example
    SELECT
      (sale_price * 1.1) * 1.05 AS final_price
    FROM
      `sales_data`;
    ```

- **공통 하위 표현식 제거(Common Subexpression Elimination)**: 공통 하위 표현식 제거는 쿼리 실행시 여러곳에서 반복적으로 사용되는 동일한 표현식(Common Subexpression)을 한번만 계산하도록 하는 최적화된 기법입니다. 아래 쿼리에서 `sale_price + tax_amount` 라는 표현식이 `subtotal` 과 `discounted_subtotal` 두곳에서 반복적으로 사용되고 있습니다. 공통 하위 표현식 제거를 적용하면 `sales_price + tax_amount` 를 한번만 계산하고, 결과를 임시 변수나 레지스터에 저장하고, 저장된 결과를 `subtotal` 과 `discounted_subtotal` 계산에 재사용(**수학에 “[치환](https://ko.wikipedia.org/wiki/%EC%B9%98%ED%99%98#:~:text=%EC%B9%98%ED%99%98%EC%9D%80%20%EC%88%98%EC%8B%9D%EC%9D%98%20%EC%96%B4%EB%96%A4,%ED%95%A8%EC%88%98%EB%A1%9C%20%EB%8C%80%EC%8B%A0%ED%95%98%EB%8A%94%20%EA%B2%83%EC%9D%B4%EB%8B%A4.)”을 생각하시면 편합니다 =p**)합니다. 해당 기술은 복잡한 함수 호출이나 연산이 많은 쿼리에서 빛을 발합니다. **동일한 계산을 여러 번 반복하는 것을 방지하여 쿼리 실행 시간을 단축시키고, 불필요한 연산 낭비를 없애줍니다.**

    ```sql
    ## Common Subexpression Elimination example
    SELECT
      (sale_price + tax_amount) AS subtotal,
      (sale_price + tax_amount) * discount_rate AS discounted_subtotal
    FROM
      `sales_data`;
    ```

- **병렬화 가능한 조인 및 집계 알고리즘(Parallelizable join and aggregation algorithms)**: 조인은 서로 다른 테이블의 특정 컬럼을 기준으로 결합하는 연산입니다. 해시 조인(Hash Join)의 경우에는 빌드 테이블의 데이터를 메모리에 해시 테이블로 만들고, 프로브 테이블의 데이터를 읽으며 해시 테이블을 검색하는 방식으로 동작합니다. 병렬화 가능한 조인 알고리즘은 이러한 과정을 여러 스레드가 동시에 수행하도록 만듭니다. 집계는 `SUM, COUNT, AVG` 와 같이 여러 행의 데이터를 그룹별로 요약하는 연산이며, 병렬화 가능한 집계 알고리즘은 이러한 집계 과정을 **로컬 집계(Local Aggregation)에서 테이블을 여러 조각으로 나눠서 여러개의 스레드에서 독립적으로 계산(병렬 처리)하고, 이후 전역 집계(Global Aggregation)에서 로컬 집계 결과를 합산하여 결과를 만듭니다**. 이방식을 통해서 각 스레드가 자신이 맡은 로컬 집계를 처리하고, 마지막에 그 결과를 합쳐서 전체를 집계 하므로 연산 속도가 매우 빨라집니다.
  
  결론적으로, **Dremel 엔진의 리프 노드(Leaf Nodes)에서 다중 스레드(Multi Threads)를 활용하여, 조인 해지 테이블 빌드 및 프로브 작업을 동시에 처리하고, 집계 시에는 로컬 및 전역 집계를 병렬로 수행하여, 쿼리 실행 속도가 크게 향상 되며, 대용량 데이터 분석 작업의 효율성을 극대화**할 수가 있습니다. 

## 2 .  Short Query Optimization: 짧은 쿼리 최적화를 통한 혁신

짧은 쿼리 최적화(Short Query Optimization)는 대시보드와 같은 BI(Business Intelligence) 도구에서 생성되는 짧고 빈번하게 실행되는 쿼리들을 극적으로 가속화하는데 사용됩니다. 일반적으로 빅쿼리는 복잡한 쿼리를 여러단계(`stage`)로 나누어 병렬로 처리 합니다. 하지만, 짧고 빈번하게 실행되는 쿼리는 이러한 다단계 분산 처리 방식을 건너 뛰고, 단일의 효율적인 단계(`single stage`)로 통합하여 실행합니다. 이를 통하여, 데이터 셔플링 및 분산처리 오버헤드를 줄여 성능과 효율성을 크게 높일 수 있습니다. 다만, 짧은 쿼리 최적화를 사용한다고 해서 [셔플(shuffle)](https://cloud.google.com/blog/products/bigquery/in-memory-query-execution-in-google-bigquery)이 아예 일어나지 않는 것은 아닙니다. 셔플은 여전히 필요할 수 있지만, 최적화를 통해 그 양과 횟수가 크게 감소하여 쿼리 성능이 향상 되는 것입니다.

<p align="center"><img width="700" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/b0bcebfd-e541-4fca-b7d2-03ea0af6b0b9">    
	
결론적으로, **짧은 쿼리 최적화 기능은 빅쿼리에서 다단계로 분산 처리되는 기존 방식의 오버헤드를 줄여 짧은 쿼리의 응답 시간을 획기적으로 개선하는 기능**입니다. 하지만 이는 셔플을 완전히 제거하는 것이 아니라, 필요한 셔플 작업을 효율적으로 최소화하여 전반적인 쿼리 성능을 향상시키는 데 목적이 있습니다.



빅쿼리를 아래의 요소들을 종합적으로 고려하여, **Short Query Optimization** 을 적용할지에 대하여 자동으로 결정합니다.

 -  **예상 데이터 스캔용량**(The estimated amount of data to be read) 
 -  **필터의 데이터 감소 효율성**(How effectively the filters are reducing the data size)
 -  **데이터의 물리적 저장 방식 및 유형**(The type and physical arrangement of the data in storage)
 - **전체적인 쿼리 구조**(The overall query structure)
 - **과거 쿼리 실행 통계**(The runtime statistics of pas query executions)
    
## 3 .  핸즈온 튜토리얼(Hands-on Tutorial)
  
  핸즈온 튜토리얼을 통하여 구글 클라우드 프로젝트 레벨에서 **Advanced Runtime** 기능을 `enable` 시키고, 샘플 쿼리문을 통하여 실제 쿼리의 성능이 얼마나 향상 되었는지, 그리고 빅쿼리의 슬롯(`slot`)사용량이 얼마나 줄었는지에 대하여 확인해 보겠습니다. 테스트 수행시에는 결과 비교를 위하여 반드시 `Query Settings` 에서 “[Use cached results”를 체크 해제](https://cloud.google.com/bigquery/docs/cached-results#disabling_retrieval_of_cached_results)하여 주시기 바랍니다.

 -  BigQuery Advanced Runtime 기능 **활성화**(2025년 9월 3일 기준으로, 해당 기능은 Public Preview 상태이며, 기본적으로 disable 되어 있습니다)

       ```sql
       ## 수행하려는 쿼리의 대상 데이터셋의 리전으로 변경: `[dataset-region].query_runtime`
       ## 튜토리얼에서는 빅쿼리 공개 데이터셋으로 진행 `region-us`
       ALTER PROJECT `[your-project-id]`
       SET OPTIONS (  
	       `region-us.query_runtime` = 'advanced'
	   );
	   ```

 - BigQuery Advanced Runtime 기능 **활성화 상태 확인**
   - 인포메이션 스키마를 통하여 활성화 상태 확인 가능(상태 변경후 인포메이션 스키마 반영까지는 최대 15초 소요)

    ```sql
    SELECT option_name, option_value
    FROM `region-us`.INFORMATION_SCHEMA.PROJECT_OPTIONS;
    ```

   - 쿼리 결과(results)에서 **option_name(query_runtime), option_value(ADVANCED)** 로 나오면 활성화(enable)된 상태
     
<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/9b5175c2-e1c1-407a-b5b6-cc70057453b5">    

-   빅쿼리 공개 데이터셋에 존재하는 샘플 테이블에서 **테스트 쿼리 수행**
    -   튜토리얼에서 사용할 데모 쿼리는 전자상거래(e-commerce) 데이터를 통하여 어떤 상품카테고리가 어느 물류센터에서, 어느 국가의 사용자에게 가장 많이 팔렸는지를 분석하는 쿼리입니다. 해당 쿼리는 `orders(주문), products(상품)` 등의 총 6개의 테이블을 조인하여, `WHERE` 절에서 명시한 칼럼`(order_id, product_id 등)` 기준으로, `GROUP BY` 구문을 통하여 그룹화여 해당 컬럼의 값을 집계`(COUNT, AVG, SUM)`하고 결과를 `total_sales_amount` 기준으로 내림차순(DESC)으로 보여주는 쿼리입니다. 해당 쿼리 수행을 통하여 쿼리 실행 결과(경과 시간, 사용된 슬롯 시간, 셔플된 바이트 용량)에 대해서 살펴 보겠습니다.
    -   테스트 수행시에는 결과 비교를 위하여 **반드시 `Query Settings` 에서 [Use cached results](https://cloud.google.com/bigquery/docs/cached-results#disabling_retrieval_of_cached_results)를 체크 해제**하여 주시기 바랍니다.

   ```sql
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
 ```


 - Advanced Runtime **활성화(enable)** 상태에서의 쿼리 수행 결과

<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/63af5b79-f630-4cc1-9dfa-b770aa21bf77">      

 -  BigQuery Advanced Runtime 기능 **비활성화**
       ```sql
       ## 수행하려는 쿼리의 대상 데이터셋의 리전으로 변경: `[dataset-region].query_runtime`
       ## 튜토리얼에서는 빅쿼리 공개 데이터셋으로 진행 `region-us`
       ALTER PROJECT `[your-project-id]`
       SET OPTIONS (  
	       `region-us.query_runtime` = null
	   );
	   ```

 - BigQuery Advanced Runtime 기능 **비활성화 상태 확인**
   -   인포메이션 스키마를 통하여 활성화 상태 확인 가능, 상태 변경후 인포메이션 스키마 반영까지는 최대 15초 소요
   

    ```sql
    SELECT option_name, option_value
    FROM `region-us`.INFORMATION_SCHEMA.PROJECT_OPTIONS;
    ```
	-   쿼리 결과(Results)내역에 **`There is no data to display.`** 로 나오면 **비활성화(disable)** 상태
<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/fd5ef653-9023-4d42-8a9a-3c594cac0e7c">    

 - Advanced Runtime **비활성화(disable)** 상태에서의 쿼리 수행 결과
     - 비활성화 상태에서 테스트 쿼리를 다시 한번 수행하여 주시기 바랍니다. 테스트 쿼리 수행시에는 **반드시 `Query Settings` 에서 [Use cached results](https://cloud.google.com/bigquery/docs/cached-results#disabling_retrieval_of_cached_results)를 체크 해제**하여 주시기 바랍니다. 

<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/f3c6fa50-013f-4092-b58e-dbbfc1965fcf">    

- **Advance Runtime 활성화 여부(enable/disable)에 따른 성능 비교 결과**

<p align="center"><img width="900" alt="Screenshot 2024-07-28 at 4 21 13 PM" src="https://github.com/user-attachments/assets/37dad518-77bb-489b-91fb-9744db908590">    

빅쿼리의 Advanced Runtime 기능을 비활성화한 상태(좌측)에서는 쿼리 실행시간이 1초 이상이며, 약20슬롯/초가 소모 되었습니다. 실행 그래프(Execution Graph) 를 살펴보면, 조인(Join) 단계와 집계(Aggregation) 단계에서 많은 시간이 소요 되었습니다. 다만, 기능을 활성화한 상태(우측)에서는 50배 이상 적은 슬롯을 소모하면서, 쿼리수행시간은 0.5초만에 완료가 되었습니다. **Advanced Runtime 기능 활성화를 통하여 빅쿼리 사용자는 더욱 빠른 쿼리 응답시간을 기대할수가 있으며, 추가로 슬롯 소모량이 줄어 들어 슬롯 요금에 대한 절감을 기대할 수 있습니다.**

## Outro(마치며..)
빅쿼리의 장점은 서버리스(Serveless), 컴퓨팅과 스토리지 노드에 대한 분리(Storage and Compute Separation ), 페타 바이트 스케일(Petabyte Scale), BQML(빅쿼리 머신러닝) , Data Security and Governance(데이터 보안 및 거버넌스) 등과 같이 많이 있지만, **가장 큰 장점 중에 하나는 바로 빅쿼리 스스로가 시간이 지남에 따라서 사용자의 개입(SQL쿼리나 데이터 스키마에 대한 변경) 없이 자동으로 쿼리 퍼포먼스 향상을 위한 진화(Self Performance Tuning)를 한다는 것이 아닐까 개인적으로 생각이 됩니다.** 끝까지 읽어 주셔서 대단히 감사합니다. **by Joon Park**

  ## 참고자료
  - [BigQuery under the hood: Enhanced vectorization in the advanced runtime](https://cloud.google.com/blog/products/data-analytics/understanding-bigquery-enhanced-vectorization)
  - [BigQuery under the hood: Short query optimizations in the advanced runtime](https://cloud.google.com/blog/products/data-analytics/short-query-optimizations-in-bigquery-advanced-runtime?e=48754805)
  - [Enable the advanced runtime](https://cloud.google.com/bigquery/docs/advanced-runtime#enable-advanced-runtime)
  - [Dremel: Interactive Analysis of Web-Scale Datasets](https://research.google/pubs/dremel-interactive-analysis-of-web-scale-datasets-2/)
  - [Colossus under the hood: a peek into Google’s scalable storage system](https://cloud.google.com/blog/products/storage-data-transfer/a-peek-behind-colossus-googles-file-system)
  - [Large-scale cluster management at Google with Borg](https://research.google/pubs/large-scale-cluster-management-at-google-with-borg/)
  - [BigQuery explained: An overview of BigQuery's architecture](https://cloud.google.com/blog/products/data-analytics/new-blog-series-bigquery-explained-overview)
  - [Overview of BigQuery Storage](https://cloud.google.com/bigquery/docs/storage_overview)
  - [Speed, scale and reliability: 25 years of Google data-center networking evolution](https://cloud.google.com/blog/products/networking/speed-scale-reliability-25-years-of-data-center-networking?e=48754805)
  - [In-memory query execution in Google BigQuery](https://cloud.google.com/blog/products/bigquery/in-memory-query-execution-in-google-bigquery)
  - [Jupiter Evolving: Transforming Google's Datacenter Network via Optical Circuit Switches and Software-Defined Networking](https://research.google/pubs/jupiter-evolving-transforming-googles-datacenter-network-via-optical-circuit-switches-and-software-defined-networking/)
  - [Single instruction, multiple data](https://en.wikipedia.org/wiki/Single_instruction,_multiple_data)
