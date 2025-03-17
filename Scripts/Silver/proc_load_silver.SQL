/*
--================================================================
--Stored Procedure : Load Silver Layer (Source -> Bronze)
--================================================================
--Script Purpose:
--	This stored procedure loads data into the 'silver' schema from external CSV files
--	It performs the following actions:
--	-> Truncates the bronze tables before Loading data.
--	-> Uses the 'BULK INSERT' command t load data from csv Files to bronze tables.
--================================================================
*/

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
	DECLARE @start_time DATETIME;
	DECLARE @end_time DATETIME;
	DECLARE @batch_start_time DATETIME
	DECLARE @batch_end_time DATETIME
	BEGIN TRY
	SET @batch_start_time = GETDATE();
		PRINT '=======================================';
		PRINT 'Loading Silver Layer';
		PRINT '=======================================';

		PRINT '---------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '---------------------------------------';

		SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_cust_info';
		TRUNCATE TABLE silver.crm_cust_info;
		-- Inserting Data into Silver
		PRINT '>> Inserting Data into silver.crm_cust_info '
		INSERT INTO silver.crm_cust_info (
			cst_id,
			cst_key,
			cst_firstname,
			cst_lastname,
			cst_marital_status,
			cst_gndr,
			cst_create_date)
		SELECT
		cst_id,
		cst_key,
		TRIM(cst_firstname) as cst_firstname,
		TRIM(cst_lastname) as cst_lastname,
		CASE WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
			WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
			ELSE 'Unkown'
		END	cst_marital_status,
		CASE WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
			WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
			ELSE 'Unkown'
		END cst_gndr,
		cst_create_date
		FROM (
		SELECT
		*,
		ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) as flag_last
		FROM bronze.crm_cust_info
		)t WHERE flag_last = 1
	SET @end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + ' Seconds';

	SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_prd_info';
		TRUNCATE TABLE silver.crm_prd_info;
		PRINT '>> Inserting date into silver.crm_prd_info'

		INSERT INTO silver.crm_prd_info (
			prd_id,
			cat_id,
			prd_key,
			prd_nm,
			prd_cost,
			prd_line,
			prd_start_dt,
			prd_end_dt
		)
		SELECT
		prd_id,
		REPLACE(SUBSTRING(prd_key,1,5),'-','_') AS cat_id,
		SUBSTRING(prd_key,7,LEN(prd_key)) AS prd_key,
		prd_nm,
		ISNULL(prd_cost,0) AS prd_cost,
		CASE  UPPER(TRIM(prd_line))
			WHEN 'M' THEN 'Mountain'
			WHEN 'R' THEN 'Road'
			WHEN 'S' THEN 'Other Sales'
			WHEN 'T' THEN 'Touring'
			ELSE 'Unkown'
		END AS prd_line,
		CAST (prd_start_dt AS DATE) AS prd_start_date,
		CAST(LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)-1 AS DATE) AS prd_end_dt
		FROM bronze.crm_prd_info;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + ' Seconds';

	SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.crm_sales_details';
		TRUNCATE TABLE silver.crm_sales_details;
		PRINT '>> Inserting data into silver.crm_sales_details'
		INSERT INTO silver.crm_sales_details (
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			sls_order_dt,
			sls_ship_dt,
			sls_due_dt,
			sls_sales,
			sls_quantity,
			sls_price
		)
		SELECT
			sls_ord_num,
			sls_prd_key,
			sls_cust_id,
			TRY_CONVERT(DATE, CONVERT(VARCHAR(8), TRY_CONVERT(INT, sls_order_dt))) AS sls_order_dt,
			TRY_CONVERT(DATE, CONVERT(VARCHAR(8), TRY_CONVERT(INT, sls_ship_dt))) AS sls_ship_dt,
			TRY_CONVERT(DATE, CONVERT(VARCHAR(8), TRY_CONVERT(INT, sls_due_dt))) AS sls_due_dt,
			CASE 
				WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
				THEN sls_quantity * ABS(sls_price)
				ELSE sls_sales
			END AS sls_sales, -- Recalculate sales if original value is missing or incorrect
			sls_quantity,
			CASE 
				WHEN sls_price IS NULL OR sls_price <= 0
				THEN sls_sales / NULLIF(sls_quantity, 0)
				ELSE sls_price -- Derive price if original value is invalid
			END AS sls_price
		FROM bronze.crm_sales_details;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + ' Seconds';

	PRINT '---------------------------------------';
	PRINT 'Loading ERP Tables';
	PRINT '---------------------------------------';

	SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_cust_az12';
		TRUNCATE TABLE silver.erp_cust_az12;
		PRINT '>> Inserting data into silver.erp_cust_az12'
		INSERT INTO silver.erp_cust_az12 (cid,bdate,gen)

		SELECT
		CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid))
			ELSE cid
		END AS cid,
		CASE WHEN bdate > GETDATE() THEN NULL
			ELSE bdate
		END AS bdate, -- Set future birthdates to NULL
		CASE 
			WHEN UPPER(TRIM(gen)) IN ('F','FEMALE') THEN 'Female'
			WHEN UPPER(TRIM(gen)) IN ('M','MALE') THEN 'Male'
			ELSE 'Unkown'
		END AS gen -- Normalize gender values and handle unknown cases

		FROM bronze.erp_cust_az12;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + ' Seconds';


	-- CLEAN AND LOAD erp_loc_a101
	SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_loc_a101';
		TRUNCATE TABLE silver.erp_loc_a101;
		PRINT '>> Inserting data into silver.erp_loc_a101'
		INSERT INTO silver.erp_loc_a101 
		(cid, cntry)
		SELECT
		REPLACE(cid, '-', '') cid,
		CASE 
			WHEN TRIM(cntry) = 'DE' THEN 'Germany' 
			WHEN TRIM(cntry) IN ('US', 'USA') THEN 'United States'
			WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'Unkown'
			ELSE TRIM(cntry)
		END AS cntry -- Normalize and Handled missing or blank country values
		FROM bronze.erp_loc_a101;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + ' Seconds';


	-- CLEAN AND LOAD erp_px_cat_g1v2
	SET @start_time = GETDATE();
		PRINT '>> Truncating Table: silver.erp_px_cat_g1v2';
		TRUNCATE TABLE silver.erp_px_cat_g1v2;
		PRINT '>> Inserting Data into silver.erp_px_cat_g1v2'
		INSERT INTO silver.erp_px_cat_g1v2
		(id,cat,subcat,maintenance)

		SELECT
		id,
		cat,
		subcat,
		maintenance
		FROM bronze.erp_px_cat_g1v2;
	SET @end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time,@end_time) AS NVARCHAR) + ' Seconds';
	
	
	
	SET @batch_end_time = GETDATE();
	PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @batch_start_time,@batch_end_time) AS NVARCHAR) + ' Seconds';
	
	END TRY
	BEGIN CATCH
		PRINT '================================================================';
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER';
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST(ERROR_MESSAGE() AS NVARCHAR);
		PRINT 'Error Message' + CAST(ERROR_STATE() AS NVARCHAR);
		PRINT '================================================================';
	END CATCH
END
