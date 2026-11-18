/* Copyright 2018 The ChromiumOS Authors
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 */

/* F75303 temperature sensor module for Chrome EC */

#include "common.h"
#include "console.h"
#include "hooks.h"
#include "i2c.h"
#include "math_util.h"
#include "temp_sensor/f75303.h"
#include "util.h"

#ifdef CONFIG_ZEPHYR
#include "temp_sensor/temp_sensor.h"
#endif

#define CPRINTS(format, args...) cprints(CC_THERMAL, format, ##args)

/*
 * Polls of a channel which have to fail in a row before the channel counts as
 * lost. Fewer failed polls keep reporting the last reading.
 */
#define F75303_LOST_AFTER_FAILED_POLLS 3

static int temps[F75303_IDX_COUNT];
/* Whether a poll of the channel has succeeded since the EC started. */
static bool has_temp[F75303_IDX_COUNT];
/* Polls of the channel which failed since the last one which succeeded. */
static uint8_t failed_polls[F75303_IDX_COUNT];
static int8_t fake_temp[F75303_IDX_COUNT];

/**
 * Records the result of a poll of channel idx: rv is its error code, and temp
 * the temperature it read when rv is EC_SUCCESS.
 */
static void record_poll(int idx, int rv, int temp)
{
	if (rv == EC_SUCCESS) {
		if (failed_polls[idx] >= F75303_LOST_AFTER_FAILED_POLLS)
			CPRINTS("F75303 channel %d readable again", idx);
		temps[idx] = temp;
		has_temp[idx] = true;
		failed_polls[idx] = 0;
		return;
	}

	if (failed_polls[idx] < F75303_LOST_AFTER_FAILED_POLLS &&
	    ++failed_polls[idx] == F75303_LOST_AFTER_FAILED_POLLS)
		CPRINTS("F75303 channel %d lost, error %d", idx, rv);
}

/**
 * Returns EC_SUCCESS when channel idx has a temperature to report, else the
 * error to report instead: EC_ERROR_HW_INTERNAL for a lost channel, and
 * EC_ERROR_NOT_POWERED for one which has not been read yet.
 */
static int reading_status(int idx)
{
	if (fake_temp[idx] != -1)
		return EC_SUCCESS;
	if (failed_polls[idx] >= F75303_LOST_AFTER_FAILED_POLLS)
		return EC_ERROR_HW_INTERNAL;
	if (!has_temp[idx])
		return EC_ERROR_NOT_POWERED;
	return EC_SUCCESS;
}

#ifndef CONFIG_ZEPHYR
/**
 * Read 8 bits register from temp sensor.
 */
static int raw_read8(const int offset, int *data)
{
	return i2c_read8(I2C_PORT_THERMAL, F75303_I2C_ADDR_FLAGS, offset, data);
}
#else
/**
 * Read 8 bits register from temp sensor.
 */
static int raw_read8(int sensor, const int offset, int *data)
{
	return i2c_read8(f75303_sensors[sensor].i2c_port,
			 f75303_sensors[sensor].i2c_addr_flags, offset, data);
}
#endif /* !CONFIG_ZEPHYR */

#ifndef CONFIG_ZEPHYR
static int get_temp(const int offset, int *temp)
{
	int rv;
	int temp_raw = 0;

	rv = raw_read8(offset, &temp_raw);
	if (rv != 0)
		return rv;

	*temp = C_TO_K(temp_raw);
	return EC_SUCCESS;
}
#else
#ifndef CONFIG_CUSTOMZIED_DESIGN
static int get_temp(int sensor, const int offset, int *temp)
{
	int rv;
	int temp_raw = 0;

	rv = raw_read8(sensor, offset, &temp_raw);
	if (rv != 0)
		return rv;

	*temp = CELSIUS_TO_MILLI_KELVIN(temp_raw);
	return EC_SUCCESS;
}
#else

static int get_temp(int sensor, const int offset, int *temp)
{
	int rv;
	int data = 0;
	int temp_raw = 0;

	/* read high byte (1 degree) and low byte (0.125 degree)*/
	switch (offset) {
	case F75303_TEMP_LOCAL_REGISTER:
		rv = raw_read8(sensor, offset, &temp_raw);
		rv = raw_read8(sensor, F75303_TEMP_LOCAL_LOW_REGISTER, &data);
		break;
	case F75303_TEMP_REMOTE1_REGISTER:
		rv = raw_read8(sensor, offset, &temp_raw);
		rv = raw_read8(sensor, F75303_TEMP_REMOTE1_LOW_REGISTER, &data);
		break;
	case F75303_TEMP_REMOTE2_REGISTER:
		rv = raw_read8(sensor, offset, &temp_raw);
		rv = raw_read8(sensor, F75303_TEMP_REMOTE2_LOW_REGISTER, &data);
		break;
	default:
		rv = EC_ERROR_INVAL;
	}

	if (rv != 0)
		return rv;

	temp_raw = (temp_raw * 1000) + ((data >> 4) * 125);
	*temp = MILLI_CELSIUS_TO_MILLI_KELVIN(temp_raw);

	return EC_SUCCESS;
}
#endif /* !CONFIG_CUSTOMIZED_DESIGN */
#endif /* !CONFIG_ZEPHYR */

int f75303_get_val(int idx, int *temp)
{
	int rv;

	if (idx < 0 || F75303_IDX_COUNT <= idx)
		return EC_ERROR_INVAL;

	if (fake_temp[idx] != -1) {
		*temp = C_TO_K(fake_temp[idx]);
		return EC_SUCCESS;
	}

	rv = reading_status(idx);
	if (rv != EC_SUCCESS)
		return rv;

	*temp = temps[idx];
	return EC_SUCCESS;
}

int f75303_get_val_k(int idx, int *temp_k_ptr)
{
	int rv;

	if (idx >= F75303_IDX_COUNT)
		return EC_ERROR_INVAL;

	rv = reading_status(idx);
	if (rv != EC_SUCCESS)
		return rv;

	*temp_k_ptr = MILLI_KELVIN_TO_KELVIN(temps[idx]);
	return EC_SUCCESS;
}

int f75303_get_val_mk(int idx, int *temp_mk_ptr)
{
	int rv;

	if (idx >= F75303_IDX_COUNT)
		return EC_ERROR_INVAL;

	rv = reading_status(idx);
	if (rv != EC_SUCCESS)
		return rv;

	*temp_mk_ptr = temps[idx];
	return EC_SUCCESS;
}

#ifndef CONFIG_ZEPHYR
static void f75303_sensor_poll(void)
{
	int temp = 0;
	int rv;

	rv = get_temp(F75303_TEMP_LOCAL_REGISTER, &temp);
	record_poll(F75303_IDX_LOCAL, rv, temp);
	rv = get_temp(F75303_TEMP_REMOTE1_REGISTER, &temp);
	record_poll(F75303_IDX_REMOTE1, rv, temp);
	rv = get_temp(F75303_TEMP_REMOTE2_REGISTER, &temp);
	record_poll(F75303_IDX_REMOTE2, rv, temp);
}
DECLARE_HOOK(HOOK_SECOND, f75303_sensor_poll, HOOK_PRIO_TEMP_SENSOR);
#else
void f75303_update_temperature(int idx)
{
	int temp_reg = 0;
	int rv = EC_ERROR_INVAL;

	if (idx >= F75303_IDX_COUNT)
		return;

	switch (idx) {
	case F75303_IDX_LOCAL:
		rv = get_temp(idx, F75303_TEMP_LOCAL_REGISTER, &temp_reg);
		break;
	case F75303_IDX_REMOTE1:
		rv = get_temp(idx, F75303_TEMP_REMOTE1_REGISTER, &temp_reg);
		break;
	case F75303_IDX_REMOTE2:
		rv = get_temp(idx, F75303_TEMP_REMOTE2_REGISTER, &temp_reg);
		break;
	default:
		rv = EC_ERROR_INVAL;
	}

	record_poll(idx, rv, temp_reg);

	if (fake_temp[idx] != -1)
		temps[idx] = KELVIN_TO_MILLI_KELVIN(C_TO_K(fake_temp[idx]));
}
#endif /* CONFIG_ZEPHYR */

static int f75303_set_fake_temp(int argc, const char **argv)
{
	int index;
	int value;
	char *e;

	if (argc != 3)
		return EC_ERROR_PARAM_COUNT;

	index = strtoi(argv[1], &e, 0);
	if ((*e) || (index < 0) || (index >= F75303_IDX_COUNT))
		return EC_ERROR_PARAM1;

	if (!strcasecmp(argv[2], "off")) {
		fake_temp[index] = -1;
		ccprintf("Turn off fake temp mode for sensor %u.\n", index);
		return EC_SUCCESS;
	}

	value = strtoi(argv[2], &e, 0);

	if ((*e) || (value < 0) || (value > 100))
		return EC_ERROR_PARAM2;

	fake_temp[index] = value;
	ccprintf("Force sensor %u = %uC.\n", index, value);

	return EC_SUCCESS;
}
DECLARE_CONSOLE_COMMAND(f75303, f75303_set_fake_temp, "<index> <value>|off",
			"Set fake temperature of sensor f75303.");

static void f75303_init(void)
{
	int index;

	for (index = 0; index < F75303_IDX_COUNT; index++)
		fake_temp[index] = -1;
}
DECLARE_HOOK(HOOK_INIT, f75303_init, HOOK_PRIO_TEMP_SENSOR);
