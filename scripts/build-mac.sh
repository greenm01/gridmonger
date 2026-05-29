#!/usr/bin/env bash

nimble releaseMacX64
nimble releaseMacArm64
nimble mergeMacUniversal
nimble packageMac
nimble publishPackageMac
