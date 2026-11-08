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

import java.util.Arrays;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.reactive.CorsWebFilter;
import org.springframework.web.cors.reactive.UrlBasedCorsConfigurationSource;

@Configuration
public class CORSConfig {

  @Bean
  @Order(Ordered.HIGHEST_PRECEDENCE)
  public CorsWebFilter corsWebFilter(
      @Value("${cors.allowed-origins:http://localhost:3000,https://metro-fe.vercel.app}")
          String allowedOrigins) {
    CorsConfiguration corsConfig = new CorsConfiguration();
    corsConfig.setAllowedOriginPatterns(parseOrigins(allowedOrigins));
    corsConfig.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
    corsConfig.setAllowedHeaders(List.of("*"));
    corsConfig.setAllowCredentials(true);
    corsConfig.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", corsConfig);

    return new CorsWebFilter(source);
  }

  /**
   * Splits a comma-separated origin list, trims whitespace, drops empty entries and removes
   * trailing slashes (browsers send the Origin header without one).
   */
  static List<String> parseOrigins(String allowedOrigins) {
    if (allowedOrigins == null) {
      return List.of();
    }
    return Arrays.stream(allowedOrigins.split(","))
        .map(String::trim)
        .map(origin -> origin.replaceAll("/+$", ""))
        .filter(origin -> !origin.isEmpty())
        .toList();
  }
}
