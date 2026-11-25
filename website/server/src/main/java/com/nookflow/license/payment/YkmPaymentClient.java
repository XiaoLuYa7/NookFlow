package com.nookflow.license.payment;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.nookflow.license.api.ApiException;
import com.nookflow.license.config.PaymentProperties;
import java.time.Duration;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.stream.Collectors;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientResponseException;

@Component
public final class YkmPaymentClient {
    private static final Logger LOGGER = LoggerFactory.getLogger(YkmPaymentClient.class);
    private static final int MAX_PROVIDER_MESSAGE_LENGTH = 160;

    private final PaymentProperties properties;
    private final PaymentCrypto crypto;
    private final ObjectMapper objectMapper;
    private final RestClient client;

    public YkmPaymentClient(
            PaymentProperties properties,
            PaymentCrypto crypto,
            ObjectMapper objectMapper
    ) {
        this.properties = properties;
        this.crypto = crypto;
        this.objectMapper = objectMapper;
        var requestFactory = new JdkClientHttpRequestFactory();
        requestFactory.setReadTimeout(Duration.ofSeconds(12));
        this.client = RestClient.builder()
                .baseUrl(normalizeBaseUrl(properties.baseUrl()))
                .requestFactory(requestFactory)
                .build();
    }

    public String createRedirect(Map<String, String> request) {
        String query = signed(request).entrySet().stream()
                .map(entry -> urlEncode(entry.getKey()) + "=" + urlEncode(entry.getValue()))
                .collect(Collectors.joining("&"));
        return normalizeBaseUrl(properties.baseUrl()) + "/api/pay/submit?" + query;
    }

    public QueryResult query(String orderNo) {
        Map<String, String> request = new LinkedHashMap<>();
        request.put("pid", properties.merchantId());
        request.put("out_trade_no", orderNo);
        request.put("timestamp", Long.toString(System.currentTimeMillis() / 1000));
        JsonNode response = post("/api/pay/query", signed(request));
        Map<String, String> values = scalarValues(response);
        assertSuccessfulSignedResponse(response, values);
        int status = response.path("status").asInt(-1);
        if (status < 0) throw new ApiException(HttpStatus.BAD_GATEWAY, "invalid_payment_response");
        return new QueryResult(
                required(values, "trade_no"),
                values.getOrDefault("type", ""),
                values.getOrDefault("money", ""),
                status
        );
    }

    private Map<String, String> signed(Map<String, String> source) {
        Map<String, String> parameters = new LinkedHashMap<>(source);
        parameters.put("sign_type", "RSA");
        parameters.put("sign", crypto.sign(parameters));
        return parameters;
    }

    private JsonNode post(String path, Map<String, String> parameters) {
        var form = new LinkedMultiValueMap<String, String>();
        parameters.forEach(form::add);
        try {
            JsonNode response = client.post()
                    .uri(path)
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                    .body(form)
                    .retrieve()
                    .body(JsonNode.class);
            if (response == null || !response.isObject()) {
                throw new ApiException(HttpStatus.BAD_GATEWAY, "invalid_payment_response");
            }
            return response;
        } catch (ApiException error) {
            throw error;
        } catch (RestClientResponseException error) {
            LOGGER.warn(
                    "YKM HTTP request failed: status={}, provider={}",
                    error.getStatusCode().value(),
                    safeProviderSummary(error.getResponseBodyAsString())
            );
            throw new ApiException(HttpStatus.BAD_GATEWAY, "payment_provider_unavailable");
        } catch (Exception error) {
            LOGGER.warn("YKM request unavailable: type={}", error.getClass().getSimpleName());
            throw new ApiException(HttpStatus.BAD_GATEWAY, "payment_provider_unavailable");
        }
    }

    private void assertSuccessfulSignedResponse(JsonNode response, Map<String, String> values) {
        int code = response.path("code").asInt(-1);
        if (code != 0) {
            LOGGER.warn("YKM rejected request: code={}, message={}", code, providerMessage(response));
            throw new ApiException(HttpStatus.BAD_GATEWAY, "payment_provider_rejected");
        }
        if (!crypto.verify(values)) {
            throw new ApiException(HttpStatus.BAD_GATEWAY, "invalid_payment_signature");
        }
    }

    private static Map<String, String> scalarValues(JsonNode object) {
        Map<String, String> values = new LinkedHashMap<>();
        object.fields().forEachRemaining(entry -> {
            if (entry.getValue().isValueNode() && !entry.getValue().isNull()) {
                values.put(entry.getKey(), entry.getValue().asText());
            }
        });
        return values;
    }

    private String safeProviderSummary(String body) {
        try {
            JsonNode response = objectMapper.readTree(body);
            return "code=" + response.path("code").asText("unknown")
                    + ", message=" + providerMessage(response);
        } catch (Exception ignored) {
            return "unparseable_response";
        }
    }

    private static String providerMessage(JsonNode response) {
        String message = response.path("msg").asText("");
        if (message.isBlank()) {
            message = response.path("message").asText("");
        }
        if (message.isBlank()) {
            return "not_provided";
        }
        String sanitized = message.replaceAll("[\\r\\n\\t]+", " ").trim();
        return sanitized.length() <= MAX_PROVIDER_MESSAGE_LENGTH
                ? sanitized
                : sanitized.substring(0, MAX_PROVIDER_MESSAGE_LENGTH);
    }

    private static String required(Map<String, String> values, String key) {
        String value = values.get(key);
        if (value == null || value.isBlank()) {
            throw new ApiException(HttpStatus.BAD_GATEWAY, "invalid_payment_response");
        }
        return value;
    }

    private static String normalizeBaseUrl(String value) {
        String base = value == null || value.isBlank() ? "https://pay.ykmcn.com" : value.trim();
        return base.endsWith("/") ? base.substring(0, base.length() - 1) : base;
    }

    private static String urlEncode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    public record QueryResult(String tradeNo, String channel, String money, int status) {
    }
}
