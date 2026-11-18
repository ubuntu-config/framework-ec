/* Copyright 2026 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

#include "common.h"
#include "emul/emul_common_i2c.h"
#include "emul/i2c_mock.h"
#include "temp_sensor/f75303.h"
#include "test/drivers/test_state.h"

#include <zephyr/drivers/emul.h>
#include <zephyr/ztest.h>

#define LOCAL_EMUL EMUL_DT_GET(DT_NODELABEL(f75303_local))
#define LOCAL_COMMON_DATA emul_i2c_mock_get_i2c_common_data(LOCAL_EMUL)

/* The temperature in whole degrees Celsius which the local channel reads. */
static int local_temp_c;

static int read_local_temp(const struct emul *target, int reg, uint8_t *val,
			   int bytes, void *data)
{
	*val = local_temp_c;
	return 0;
}

static void f75303_before(void *fixture)
{
	i2c_mock_reset(LOCAL_EMUL);
	i2c_common_emul_set_read_func(LOCAL_COMMON_DATA, read_local_temp, NULL);
}

ZTEST_SUITE(f75303, drivers_predicate_post_main, NULL, f75303_before, NULL,
	    NULL);

ZTEST(f75303, test_channel_not_read_yet)
{
	int temp;

	/* Nothing polls the remote1 channel. */
	zassert_equal(f75303_get_val_k(F75303_IDX_REMOTE1, &temp),
		      EC_ERROR_NOT_POWERED);
	zassert_equal(f75303_get_val_mk(F75303_IDX_REMOTE1, &temp),
		      EC_ERROR_NOT_POWERED);
}

ZTEST(f75303, test_lost_channel)
{
	int temp;

	local_temp_c = 40;
	f75303_update_temperature(F75303_IDX_LOCAL);
	zassert_ok(f75303_get_val_k(F75303_IDX_LOCAL, &temp));
	zassert_equal(temp, C_TO_K(40));

	/* Polls which fail keep the last reading until there are enough. */
	i2c_common_emul_set_read_fail_reg(LOCAL_COMMON_DATA,
					  I2C_COMMON_EMUL_FAIL_ALL_REG);
	f75303_update_temperature(F75303_IDX_LOCAL);
	f75303_update_temperature(F75303_IDX_LOCAL);
	zassert_ok(f75303_get_val_k(F75303_IDX_LOCAL, &temp));
	zassert_equal(temp, C_TO_K(40));

	f75303_update_temperature(F75303_IDX_LOCAL);
	zassert_equal(f75303_get_val_k(F75303_IDX_LOCAL, &temp),
		      EC_ERROR_HW_INTERNAL);
	zassert_equal(f75303_get_val_mk(F75303_IDX_LOCAL, &temp),
		      EC_ERROR_HW_INTERNAL);

	/* A poll which succeeds reports readings again. */
	i2c_common_emul_set_read_fail_reg(LOCAL_COMMON_DATA,
					  I2C_COMMON_EMUL_NO_FAIL_REG);
	local_temp_c = 45;
	f75303_update_temperature(F75303_IDX_LOCAL);
	zassert_ok(f75303_get_val_k(F75303_IDX_LOCAL, &temp));
	zassert_equal(temp, C_TO_K(45));
}
