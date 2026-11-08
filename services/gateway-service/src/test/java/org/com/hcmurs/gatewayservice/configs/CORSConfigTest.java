/**
 * Copyright (c) 2025 hcmurs. All rights reserved.
 *
 * Service: Gateway-Service
 *
 * This software is the confidential and proprietary information of hcmurs.
 * You shall not disclose such confidential information and shall use it only in
 * accordance with the terms of the license agreement you entered into with hcmurs.
 */
package org.com.hcmurs.gatewayservice.configs;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.List;
import org.junit.jupiter.api.Test;

class CORSConfigTest {

  @Test
  void parseOriginsSplitsTrimsAndRemovesTrailingSlash() {
    assertEquals(
        List.of("https://metro.test.name.vn", "https://metro-fe.vercel.app"),
        CORSConfig.parseOrigins(" https://metro.test.name.vn , https://metro-fe.vercel.app/ "));
  }

  @Test
  void parseOriginsDropsEmptyEntries() {
    assertEquals(
        List.of("http://localhost:3000"), CORSConfig.parseOrigins("http://localhost:3000,, ,"));
  }

  @Test
  void parseOriginsHandlesNullAndBlank() {
    assertEquals(List.of(), CORSConfig.parseOrigins(null));
    assertEquals(List.of(), CORSConfig.parseOrigins(""));
  }
}
