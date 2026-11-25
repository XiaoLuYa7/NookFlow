package com.nookflow.license.payment;

import static org.assertj.core.api.Assertions.assertThat;

import java.lang.reflect.Constructor;
import java.util.Arrays;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

final class PaymentServiceConstructorTest {
    @Test
    void productionConstructorIsExplicitlyAutowired() {
        Constructor<?>[] constructors = PaymentService.class.getDeclaredConstructors();

        assertThat(Arrays.stream(constructors)
                .filter(constructor -> constructor.isAnnotationPresent(Autowired.class)))
                .hasSize(1);
    }
}
