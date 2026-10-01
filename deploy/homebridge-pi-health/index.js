'use strict';

const fs = require('fs');
const http = require('http');
const { execFile } = require('child_process');

const PLUGIN_NAME = 'homebridge-pi-control-health';
const PLATFORM_NAME = 'PiControlHealth';

module.exports = (api) => {
  api.registerPlatform(PLUGIN_NAME, PLATFORM_NAME, PiControlHealthPlatform);
};

class PiControlHealthPlatform {
  constructor(log, config, api) {
    this.log = log;
    this.config = config || {};
    this.api = api;
    this.Service = api.hap.Service;
    this.Characteristic = api.hap.Characteristic;
    this.accessories = new Map();
    this.timer = null;
    this.polling = false;

    this.mountPath = this.config.mountPath || '/mnt/pishare';
    this.serviceUrl = this.config.serviceUrl || 'http://127.0.0.1:8080/';
    this.ngrokApiUrl = this.config.ngrokApiUrl || 'http://127.0.0.1:4040/api/tunnels';
    this.storageWarningPercent = clampNumber(this.config.storageWarningPercent, 50, 99, 90);
    this.temperatureWarningC = clampNumber(this.config.temperatureWarningC, 40, 90, 70);
    this.pollIntervalSeconds = clampNumber(this.config.pollIntervalSeconds, 30, 3600, 60);

    this.checks = [
      { id: 'nas', name: 'NAS Warnung', check: () => this.checkNas() },
      { id: 'storage', name: 'Speicher Warnung', check: () => this.checkStorage() },
      { id: 'pi-control', name: 'Pi-Control Warnung', check: () => this.checkHttp(this.serviceUrl) },
      { id: 'remote-access', name: 'Fernzugriff Warnung', check: () => this.checkNgrok() },
      { id: 'temperature', name: 'Temperatur Warnung', check: () => this.checkTemperature() },
      { id: 'docker', name: 'Docker Warnung', check: () => this.checkService('docker') },
      { id: 'samba', name: 'NAS-Dateidienst Warnung', check: () => this.checkService('smbd') },
    ];

    api.on('didFinishLaunching', () => this.start());
    api.on('shutdown', () => {
      if (this.timer) clearInterval(this.timer);
    });
  }

  configureAccessory(accessory) {
    this.accessories.set(accessory.context.checkId, accessory);
  }

  start() {
    const activeIds = new Set(this.checks.map((item) => item.id));
    for (const accessory of this.accessories.values()) {
      if (!activeIds.has(accessory.context.checkId)) {
        this.api.unregisterPlatformAccessories(PLUGIN_NAME, PLATFORM_NAME, [accessory]);
      }
    }

    for (const item of this.checks) this.ensureAccessory(item);
    this.poll();
    this.timer = setInterval(() => this.poll(), this.pollIntervalSeconds * 1000);
    this.timer.unref?.();
  }

  ensureAccessory(item) {
    let accessory = this.accessories.get(item.id);
    if (!accessory) {
      const uuid = this.api.hap.uuid.generate(`${PLUGIN_NAME}:${item.id}`);
      accessory = new this.api.platformAccessory(item.name, uuid);
      accessory.context.checkId = item.id;
      this.api.registerPlatformAccessories(PLUGIN_NAME, PLATFORM_NAME, [accessory]);
      this.accessories.set(item.id, accessory);
    }

    accessory.displayName = item.name;
    const info = accessory.getService(this.Service.AccessoryInformation);
    info.setCharacteristic(this.Characteristic.Manufacturer, 'Pi Control');
    info.setCharacteristic(this.Characteristic.Model, 'Server-Warnmelder');
    info.setCharacteristic(this.Characteristic.SerialNumber, item.id);

    const sensor = accessory.getService(this.Service.ContactSensor)
      || accessory.addService(this.Service.ContactSensor, item.name);
    sensor.setCharacteristic(this.Characteristic.Name, item.name);
  }

  async poll() {
    if (this.polling) return;
    this.polling = true;
    try {
      const results = await Promise.all(this.checks.map(async (item) => {
        try {
          return { item, problem: await item.check() };
        } catch (error) {
          this.log.warn('%s konnte nicht geprüft werden: %s', item.name, error.message);
          return { item, problem: true };
        }
      }));

      for (const { item, problem } of results) this.updateSensor(item, problem);
    } finally {
      this.polling = false;
    }
  }

  updateSensor(item, problem) {
    const accessory = this.accessories.get(item.id);
    if (!accessory) return;
    const sensor = accessory.getService(this.Service.ContactSensor);
    const previous = accessory.context.problem;
    accessory.context.problem = problem;
    sensor.updateCharacteristic(
      this.Characteristic.ContactSensorState,
      problem
        ? this.Characteristic.ContactSensorState.CONTACT_NOT_DETECTED
        : this.Characteristic.ContactSensorState.CONTACT_DETECTED,
    );
    sensor.updateCharacteristic(
      this.Characteristic.StatusFault,
      problem
        ? this.Characteristic.StatusFault.GENERAL_FAULT
        : this.Characteristic.StatusFault.NO_FAULT,
    );
    if (previous !== undefined && previous !== problem) {
      this.log[problem ? 'warn' : 'info']('%s: %s', item.name, problem ? 'Problem erkannt' : 'wieder normal');
    }
  }

  async checkNas() {
    const mounts = await fs.promises.readFile('/proc/mounts', 'utf8');
    const mounted = mounts.split('\n').some((line) => line.split(' ')[1] === this.mountPath);
    if (!mounted) return true;
    try {
      await fs.promises.access(this.mountPath, fs.constants.R_OK);
      return false;
    } catch (_) {
      return true;
    }
  }

  async checkStorage() {
    const paths = ['/', this.mountPath];
    const percentages = await Promise.all(paths.map((path) => diskPercent(path)));
    return percentages.some((value) => value >= this.storageWarningPercent);
  }

  async checkTemperature() {
    const raw = await fs.promises.readFile('/sys/class/thermal/thermal_zone0/temp', 'utf8');
    return Number(raw.trim()) / 1000 >= this.temperatureWarningC;
  }

  async checkService(name) {
    try {
      const output = await run('/bin/systemctl', ['is-active', name]);
      return output.trim() !== 'active';
    } catch (_) {
      return true;
    }
  }

  checkHttp(url) {
    return httpProblem(url, false);
  }

  checkNgrok() {
    return httpProblem(this.ngrokApiUrl, true);
  }
}

function clampNumber(value, minimum, maximum, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= minimum && parsed <= maximum ? parsed : fallback;
}

function run(file, args) {
  return new Promise((resolve, reject) => {
    execFile(file, args, { timeout: 5000, encoding: 'utf8' }, (error, stdout) => {
      if (error) reject(error);
      else resolve(stdout);
    });
  });
}

async function diskPercent(path) {
  const output = await run('/bin/df', ['-Pk', path]);
  const rows = output.trim().split('\n');
  const fields = rows[rows.length - 1].trim().split(/\s+/);
  const value = Number(String(fields[4] || '').replace('%', ''));
  if (!Number.isFinite(value)) throw new Error(`Speicherwert für ${path} ist ungültig`);
  return value;
}

function httpProblem(url, expectTunnel) {
  return new Promise((resolve) => {
    const request = http.get(url, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => {
        if (body.length < 65536) body += chunk;
      });
      response.on('end', () => {
        if (response.statusCode < 200 || response.statusCode >= 400) return resolve(true);
        if (!expectTunnel) return resolve(false);
        try {
          const data = JSON.parse(body);
          resolve(!Array.isArray(data.tunnels) || data.tunnels.length === 0);
        } catch (_) {
          resolve(true);
        }
      });
    });
    request.setTimeout(5000, () => request.destroy());
    request.on('error', () => resolve(true));
  });
}
